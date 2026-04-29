defmodule ControlKeelWeb.ObservabilityRecommendationsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "recommendations page renders prioritized local actions", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Recommendation page issue",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.recommendations_page"
    })

    {:ok, view, html} = live(conn, ~p"/observability/recommendations")

    assert html =~ "Recommendations"
    assert has_element?(view, "#observability-recommendations-page")
    assert has_element?(view, "#observability-recommendations-health")
    assert has_element?(view, "#observability-recommendations-summary")
    assert has_element?(view, "#observability-recommendations-list")
    assert html =~ "Regression eval for security.recommendations_page"
    assert html =~ "/observability/problems"
  end
end
