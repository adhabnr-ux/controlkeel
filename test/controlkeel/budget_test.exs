defmodule ControlKeel.BudgetTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  import ControlKeel.MissionFixtures

  test "estimate is read-only and commit writes an invocation plus spend" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 600, spent_cents: 200})
    task = task_fixture(%{session: session})

    assert {:ok, estimate} =
             Budget.estimate(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "estimated_cost_cents" => 150
             })

    assert estimate["recorded"] == false
    assert Repo.aggregate(Invocation, :count, :id) == 0

    assert {:ok, committed} =
             Budget.commit(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "estimated_cost_cents" => 150
             })

    assert committed["recorded"] == true
    assert Repo.aggregate(Invocation, :count, :id) == 1
    assert Mission.get_session!(session.id).spent_cents == 350
  end

  test "rejects unknown model pricing without explicit estimated cost" do
    session = session_fixture()

    assert {:error, {:invalid_arguments, message}} =
             Budget.estimate(%{
               "session_id" => session.id,
               "provider" => "anthropic",
               "model" => "unknown-model",
               "input_tokens" => 1_000,
               "output_tokens" => 100
             })

    assert message =~ "Unknown model pricing"
  end

  test "warns near the session cap and blocks above the rolling 24h cap" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 300, spent_cents: 750})

    assert {:ok, warning} =
             Budget.estimate(%{
               "session_id" => session.id,
               "estimated_cost_cents" => 60
             })

    assert warning["decision"] == "warn"

    recent = DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.truncate(:second)
    old = DateTime.utc_now() |> DateTime.add(-30, :hour) |> DateTime.truncate(:second)

    Repo.insert_all(Invocation, [
      %{
        session_id: session.id,
        source: "mcp",
        tool: "ck_budget",
        estimated_cost_cents: 250,
        decision: "allow",
        metadata: %{},
        inserted_at: recent,
        updated_at: recent
      },
      %{
        session_id: session.id,
        source: "mcp",
        tool: "ck_budget",
        estimated_cost_cents: 999,
        decision: "allow",
        metadata: %{},
        inserted_at: old,
        updated_at: old
      }
    ])

    assert Budget.rolling_24h_spend_cents(session.id) == 250

    assert {:ok, blocked} =
             Budget.estimate(%{
               "session_id" => session.id,
               "estimated_cost_cents" => 80
             })

    assert blocked["decision"] == "block"
    assert blocked["summary"] =~ "rolling 24-hour budget"
  end

  describe "amplification_ratios/1" do
    test "returns empty list when no invocations exist" do
      assert [] = Budget.amplification_ratios()
    end

    test "computes ratio for a session with token data" do
      session = session_fixture(%{budget_cents: 10_000, spent_cents: 0})

      Repo.insert!(%Invocation{
        source: "proxy",
        tool: "chat",
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        input_tokens: 100,
        output_tokens: 400,
        estimated_cost_cents: 10,
        decision: "allow",
        metadata: %{},
        session_id: session.id
      })

      ratios = Budget.amplification_ratios(since_hours: 1)
      assert length(ratios) >= 1

      row = Enum.find(ratios, &(&1.session_id == session.id))
      assert row.input_tokens == 100
      assert row.output_tokens == 400
      assert row.ratio == 4.0
    end

    test "orders results by descending ratio" do
      s1 = session_fixture(%{budget_cents: 10_000, spent_cents: 0})
      s2 = session_fixture(%{budget_cents: 10_000, spent_cents: 0})

      Repo.insert!(%Invocation{
        source: "proxy",
        tool: "chat",
        provider: "openai",
        model: "gpt-4",
        input_tokens: 100,
        output_tokens: 1_000,
        estimated_cost_cents: 5,
        decision: "allow",
        metadata: %{},
        session_id: s1.id
      })

      Repo.insert!(%Invocation{
        source: "proxy",
        tool: "chat",
        provider: "openai",
        model: "gpt-4",
        input_tokens: 200,
        output_tokens: 200,
        estimated_cost_cents: 5,
        decision: "allow",
        metadata: %{},
        session_id: s2.id
      })

      ratios = Budget.amplification_ratios(since_hours: 1)
      filtered = Enum.filter(ratios, &(&1.session_id in [s1.id, s2.id]))

      assert length(filtered) == 2
      [first | _] = filtered
      assert first.session_id == s1.id
      assert first.ratio == 10.0
    end

    test "respects the since_hours window" do
      session = session_fixture(%{budget_cents: 10_000, spent_cents: 0})

      Repo.insert!(%Invocation{
        source: "proxy",
        tool: "chat",
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        input_tokens: 50,
        output_tokens: 50,
        estimated_cost_cents: 1,
        decision: "allow",
        metadata: %{},
        session_id: session.id,
        inserted_at: ~U[2000-01-01 00:00:00Z]
      })

      assert [] = Budget.amplification_ratios(since_hours: 1)
    end
  end
end
