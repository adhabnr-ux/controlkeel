defmodule ControlKeelWeb.ObservabilityEvalsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "eval candidates page renders advisory problem-derived candidates", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval page issue",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.eval_page"
    })

    {:ok, view, html} = live(conn, ~p"/observability/evals")

    assert html =~ "Eval candidates"
    assert has_element?(view, "#observability-evals-page")
    assert has_element?(view, "#observability-evals-health")
    assert has_element?(view, "#observability-evals-summary")
    assert has_element?(view, "#observability-evals-list")
    assert html =~ "Regression eval for security.eval_page"
    assert html =~ "security-regression"
    assert html =~ "/observability/problems"
    assert html =~ "/benchmarks"
  end
end
