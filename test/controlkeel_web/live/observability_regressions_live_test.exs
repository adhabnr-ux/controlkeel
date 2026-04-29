defmodule ControlKeelWeb.ObservabilityRegressionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.BenchmarkFixtures
  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "regressions page renders benchmark posture", %{conn: conn} do
    session = session_fixture()
    _run = benchmark_run_fixture()

    finding_fixture(%{
      session: session,
      title: "Regression page finding",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.regression_page"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    {:ok, view, html} = live(conn, ~p"/observability/regressions")

    assert html =~ "Regression tracking"
    assert has_element?(view, "#observability-regressions-page")
    assert has_element?(view, "#observability-regressions-health")
    assert has_element?(view, "#observability-regressions-runs")
    assert has_element?(view, "#observability-regressions-catch-rate")
    assert has_element?(view, "#observability-regressions-draft-coverage")
    assert has_element?(view, "#observability-regressions-recommendations")
    assert has_element?(view, "#observability-regressions-runs-list")
  end
end
