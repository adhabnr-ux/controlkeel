defmodule ControlKeelWeb.ObservabilityTrendsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  test "trends page renders local observability trends", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Trend page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.trend_page"
    })

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "opencode",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               estimated_cost_cents: 9,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    {:ok, view, html} = live(conn, ~p"/observability/trends")

    assert html =~ "Local trends"
    assert has_element?(view, "#observability-trends-page")
    assert has_element?(view, "#observability-trends-window")
    assert has_element?(view, "#observability-trends-runs")
    assert has_element?(view, "#observability-trends-findings")
    assert has_element?(view, "#observability-trends-costs")
    assert has_element?(view, "#observability-trends-imports")
    assert has_element?(view, "#observability-trends-recommendations")
    assert has_element?(view, "#observability-trends-series")
    assert html =~ "1 red"
    assert html =~ "Findings"
  end
end
