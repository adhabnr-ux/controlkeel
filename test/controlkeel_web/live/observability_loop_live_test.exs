defmodule ControlKeelWeb.ObservabilityLoopLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "loop page renders read-only learning loop status", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Loop page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.loop_page"
    })

    {:ok, view, html} = live(conn, ~p"/observability/loop")

    assert html =~ "Learning loop"
    assert has_element?(view, "#observability-loop-page")
    assert has_element?(view, "#observability-loop-health")
    assert has_element?(view, "#observability-loop-boundary")
    assert has_element?(view, "#observability-loop-summary")
    assert has_element?(view, "#observability-loop-blockers")
    assert has_element?(view, "#observability-loop-actions")
    assert has_element?(view, "#observability-loop-recommendations")
    assert html =~ "Automatic benchmark execution: false"
    assert html =~ "Automatic promotion: false"
    assert html =~ "active_problems"
  end
end
