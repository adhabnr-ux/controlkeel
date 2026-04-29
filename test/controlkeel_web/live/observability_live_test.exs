defmodule ControlKeelWeb.ObservabilityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "dedicated observability page renders session run details", %{conn: conn} do
    session = session_fixture(%{budget_cents: 2_000, daily_budget_cents: 2_000, spent_cents: 300})
    task = task_fixture(%{session: session, status: "in_progress", title: "Observe task"})

    finding_fixture(%{
      session: session,
      title: "Observable finding",
      severity: "high",
      status: "open",
      rule_id: "observability.test"
    })

    assert {:ok, _review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "review_type" => "plan",
               "title" => "Observation review",
               "submission_body" => "Review this run"
             })

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}")

    assert html =~ "Session run observability"
    assert has_element?(view, "#observability-run-page")
    assert has_element?(view, "#observability-health-card")
    assert has_element?(view, "#observability-timeline")
    assert has_element?(view, "#observability-findings")
    assert has_element?(view, "#observability-gates")
    assert has_element?(view, "#observability-costs")
    assert has_element?(view, "#observability-tools")
    assert has_element?(view, "#observability-recommendations")
    assert html =~ "Observable finding"
    assert html =~ "Observation review"
  end

  test "dedicated observability page redirects missing sessions", %{conn: conn} do
    assert {:error,
            {:live_redirect, %{to: "/", flash: %{"error" => "Session observability not found."}}}} =
             live(conn, ~p"/observability/sessions/999999")
  end

  test "mission control links to dedicated observability page", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})

    {:ok, _view, html} = live(conn, ~p"/missions/#{session.id}")

    assert html =~ "mission-observability-open"
    assert html =~ "Open run observability"
    assert html =~ "/observability/sessions/#{session.id}"
  end
end
