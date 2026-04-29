defmodule ControlKeelWeb.ObservabilityBenchmarkHistoryLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "benchmark history page renders readiness and coverage", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "History page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.history_page"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [%{id: draft_id}]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    assert {:ok, _result} =
             Observability.update_benchmark_draft_status(draft_id, "approved",
               reviewed_by: "test"
             )

    assert %{materialized: 1} =
             Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

    {:ok, view, html} = live(conn, ~p"/observability/benchmarks/history")

    assert html =~ "Benchmark history"
    assert has_element?(view, "#observability-benchmark-history-page")
    assert has_element?(view, "#observability-benchmark-history-readiness")
    assert has_element?(view, "#observability-benchmark-history-summary")
    assert has_element?(view, "#observability-benchmark-history-recommendations")
    assert has_element?(view, "#observability-benchmark-history-runs")
    assert html =~ "Materialized"
    assert html =~ "No observability benchmark runs yet"
  end
end
