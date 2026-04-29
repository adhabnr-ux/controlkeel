defmodule ControlKeelWeb.ObservabilityBenchmarkScenariosLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "benchmark scenarios page renders materialized scenarios", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Scenario page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.scenario_page"
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

    {:ok, view, html} = live(conn, ~p"/observability/benchmarks/scenarios")

    assert html =~ "Materialized benchmark scenarios"
    assert has_element?(view, "#observability-benchmark-scenarios-page")
    assert has_element?(view, "#observability-benchmark-scenarios-count")
    assert has_element?(view, "#observability-benchmark-scenarios-summary")
    assert has_element?(view, "#observability-benchmark-scenarios-list")
    assert has_element?(view, "#observability-benchmark-run-guidance")
    assert html =~ "Benchmark draft for security.scenario_page"
    assert html =~ "security.scenario_page"
    assert html =~ "Human-gated execution"
    assert html =~ "controlkeel obs benchmarks run"
    refute html =~ "phx-click=\"run"
  end
end
