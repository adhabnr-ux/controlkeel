defmodule ControlKeel.Cloud.BaselineAnalyzerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Cloud.BaselineAnalyzer
  alias ControlKeel.Cloud.WorkspaceBaseline
  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  import ControlKeel.MissionFixtures

  setup do
    workspace = workspace_fixture()
    {:ok, workspace: workspace}
  end

  describe "compute_and_store/2" do
    test "returns ok with zero sample sessions for empty workspace", %{workspace: ws} do
      assert {:ok, baseline} = BaselineAnalyzer.compute_and_store(ws.id)
      assert baseline.workspace_id == ws.id
      assert baseline.sample_sessions == 0
      assert WorkspaceBaseline.decode(baseline) == %{}
    end

    test "computes per-tool means from invocations", %{workspace: ws} do
      s1 = session_fixture(%{workspace_id: ws.id})
      s2 = session_fixture(%{workspace_id: ws.id})

      for session <- [s1, s2] do
        Repo.insert!(%Invocation{
          source: "proxy", tool: "ck_validate", provider: "anthropic", model: "claude-sonnet-4-6",
          input_tokens: 100, output_tokens: 200,
          estimated_cost_cents: 5, decision: "allow", metadata: %{},
          session_id: session.id
        })
      end

      assert {:ok, baseline} = BaselineAnalyzer.compute_and_store(ws.id, window_days: 7)
      assert baseline.sample_sessions == 2

      data = WorkspaceBaseline.decode(baseline)
      assert Map.has_key?(data, "ck_validate")
      assert data["ck_validate"]["mean_calls_per_session"] == 1.0
      assert data["ck_validate"]["mean_input_tokens"] == 100.0
    end

    test "upserts on second call", %{workspace: ws} do
      {:ok, _} = BaselineAnalyzer.compute_and_store(ws.id)
      {:ok, second} = BaselineAnalyzer.compute_and_store(ws.id)
      assert second.workspace_id == ws.id
      assert Repo.aggregate(WorkspaceBaseline, :count, :id) == 1
    end
  end

  describe "detect_deviations/2" do
    test "returns empty list when no baseline stored", %{workspace: ws} do
      session = session_fixture(%{workspace_id: ws.id})
      assert [] = BaselineAnalyzer.detect_deviations(session)
    end

    test "returns empty list when baseline has too few samples", %{workspace: ws} do
      Repo.insert!(%WorkspaceBaseline{
        workspace_id: ws.id, window_days: 7,
        baseline_data: ~s({"ck_validate": {"mean_calls_per_session": 1.0, "mean_input_tokens": 100.0, "mean_output_tokens": 200.0, "sample_count": 2}}),
        sample_sessions: 2,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      session = session_fixture(%{workspace_id: ws.id})
      assert [] = BaselineAnalyzer.detect_deviations(session)
    end

    test "detects call-count deviation above threshold", %{workspace: ws} do
      Repo.insert!(%WorkspaceBaseline{
        workspace_id: ws.id, window_days: 7,
        baseline_data: Jason.encode!(%{
          "ck_validate" => %{
            "mean_calls_per_session" => 1.0,
            "mean_input_tokens" => 100.0,
            "mean_output_tokens" => 200.0,
            "sample_count" => 10
          }
        }),
        sample_sessions: 10,
        computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      session = session_fixture(%{workspace_id: ws.id})

      for _ <- 1..5 do
        Repo.insert!(%Invocation{
          source: "proxy", tool: "ck_validate", provider: "anthropic", model: "c",
          input_tokens: 100, output_tokens: 200,
          estimated_cost_cents: 1, decision: "allow", metadata: %{},
          session_id: session.id
        })
      end

      deviations = BaselineAnalyzer.detect_deviations(session, window_hours: 1)
      call_deviation = Enum.find(deviations, &(&1.metric == :calls))
      assert call_deviation != nil
      assert call_deviation.tool == "ck_validate"
      assert call_deviation.ratio >= 3.0
    end
  end

  describe "get_baseline/1" do
    test "returns nil when no baseline stored", %{workspace: ws} do
      assert nil == BaselineAnalyzer.get_baseline(ws.id)
    end

    test "returns stored baseline", %{workspace: ws} do
      {:ok, _} = BaselineAnalyzer.compute_and_store(ws.id)
      assert %WorkspaceBaseline{} = BaselineAnalyzer.get_baseline(ws.id)
    end
  end
end
