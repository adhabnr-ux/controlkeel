defmodule ControlKeelWeb.ObservabilityOverviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "overview page renders workspace observability cockpit", %{conn: conn} do
    session = session_fixture(%{budget_cents: 2_000, spent_cents: 450})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview grouped finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    {:ok, view, html} = live(conn, ~p"/observability")

    assert html =~ "Workspace overview"
    assert has_element?(view, "#observability-overview-page")
    assert has_element?(view, "#observability-overview-health")
    assert has_element?(view, "#observability-overview-runs")
    assert has_element?(view, "#observability-overview-problems")
    assert has_element?(view, "#observability-overview-costs")
    assert has_element?(view, "#observability-overview-telemetry")
    assert has_element?(view, "#observability-overview-recommendations")
    assert has_element?(view, "#observability-overview-run-list")
    assert has_element?(view, "#observability-overview-problem-list")
    assert html =~ "security.overview"
    assert html =~ "/observability/problems"
    assert html =~ "/observability/costs"
    assert html =~ "/observability/recommendations"
    assert html =~ "/observability/evals"
    assert html =~ "/observability/evals/persisted"
    assert html =~ "/observability/benchmarks/drafts"
    assert html =~ "/observability/compare"
    assert html =~ "/observability/imports"
    assert html =~ "/observability/memory-quality"
    assert html =~ "/observability/trends"
    assert html =~ "/observability/sessions/#{session.id}"
    assert html =~ "/observability/sessions/#{session.id}/export.json"
  end
end
