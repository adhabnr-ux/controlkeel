defmodule ControlKeelWeb.ObservabilityProblemsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "problems page renders grouped active findings", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "SQL grouped finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.sql_injection"
    })

    {:ok, view, html} = live(conn, ~p"/observability/problems")

    assert html =~ "Problems"
    assert has_element?(view, "#observability-problems-page")
    assert has_element?(view, "#observability-problem-list")
    assert has_element?(view, "#observability-problem-recommendations")
    assert html =~ "security.sql_injection"
    assert html =~ "SQL grouped finding"
    assert html =~ "Feedback loop"
    assert html =~ "Regression eval for security.sql_injection"
    assert html =~ "Open benchmarks"
    assert html =~ "/observability/sessions/#{session.id}"
  end

  test "run observability page links to problems", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    {:ok, view, _html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert has_element?(view, "#observability-open-problems", "Open problems")
  end
end
