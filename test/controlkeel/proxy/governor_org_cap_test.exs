defmodule ControlKeel.Proxy.GovernorOrgCapTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Proxy.Governor

  describe "workspace_org_cap_status/1" do
    test "returns :ok for unaffiliated workspaces" do
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-solo-#{System.unique_integer([:positive])}"})
      assert :ok = Accounts.workspace_org_cap_status(ws.id)
    end

    test "returns :ok when org has no budget cap set" do
      {:ok, org} = Accounts.create_org(%{name: "NoCap", slug: "no-cap-#{System.unique_integer([:positive])}"})
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)

      assert :ok = Accounts.workspace_org_cap_status(ws.id)
    end

    test "returns :ok when under cap" do
      {:ok, org} = Accounts.create_org(%{name: "Under", slug: "under-#{System.unique_integer([:positive])}"})
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      _ = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 200})
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1000)

      assert :ok = Accounts.workspace_org_cap_status(ws.id)
    end

    test "returns {:over_cap, status} when org spend exceeds cap" do
      {:ok, org} = Accounts.create_org(%{name: "Over", slug: "over-#{System.unique_integer([:positive])}"})
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      _ = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 2000})
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1000)

      assert {:over_cap, status} = Accounts.workspace_org_cap_status(ws.id)
      assert status.over_cap?
      assert status.spent_cents == 2000
      assert status.budget_cents == 1000
    end
  end

  describe "Governor.preflight/5 org-cap blocking" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "Budget Org", slug: "budget-#{System.unique_integer([:positive])}"})
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      {:ok, org: org, workspace: ws}
    end

    test "blocks when org is over cap and surfaces a cost finding", %{
      org: org,
      workspace: ws
    } do
      session = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 5_000})
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1_000)

      {:ok, preflight} =
        Governor.preflight(session, :openai, "/v1/chat/completions", %{
          model: "gpt-4o",
          text: "hello world",
          max_output_tokens: 10
        })

      refute preflight.allowed
      assert preflight.decision == "block"

      assert Enum.any?(preflight.findings, fn finding ->
               finding.rule_id == "cost.org_budget_cap_exceeded" and
                 finding.decision == "block"
             end)
    end

    test "allows when under cap", %{org: org, workspace: ws} do
      session = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 100})
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 10_000)

      {:ok, preflight} =
        Governor.preflight(session, :openai, "/v1/chat/completions", %{
          model: "gpt-4o",
          text: "hello world",
          max_output_tokens: 10
        })

      refute Enum.any?(preflight.findings, &(&1.rule_id == "cost.org_budget_cap_exceeded"))
    end

    test "no org-cap finding emitted when workspace is unaffiliated" do
      solo_ws = MissionFixtures.workspace_fixture(%{slug: "ws-solo-#{System.unique_integer([:positive])}"})
      session = MissionFixtures.session_fixture(%{workspace: solo_ws, spent_cents: 999_999})

      {:ok, preflight} =
        Governor.preflight(session, :openai, "/v1/chat/completions", %{
          model: "gpt-4o",
          text: "hello",
          max_output_tokens: 5
        })

      refute Enum.any?(preflight.findings, &(&1.rule_id == "cost.org_budget_cap_exceeded"))
    end
  end
end
