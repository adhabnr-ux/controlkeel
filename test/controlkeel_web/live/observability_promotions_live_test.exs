defmodule ControlKeelWeb.ObservabilityPromotionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "promotions page renders advisory promotion candidates", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Promotion page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.promotion_page"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    {:ok, view, html} = live(conn, ~p"/observability/promotions")

    assert html =~ "Promotion candidates"
    assert has_element?(view, "#observability-promotions-page")
    assert has_element?(view, "#observability-promotions-count")
    assert has_element?(view, "#observability-promotions-summary")
    assert has_element?(view, "#observability-promotions-recommendations")
    assert has_element?(view, "#observability-promotions-list")
    assert html =~ "Promotion execution: false"
    assert html =~ "security.promotion_page"
    assert html =~ "needs_draft"
  end
end
