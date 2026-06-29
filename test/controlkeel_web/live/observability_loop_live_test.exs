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

    {:ok, _view, html} = live(conn, ~p"/observability/loop")

    assert html =~ "Learning loop"
    assert html =~ "Safety boundary"
    assert html =~ "Automatic benchmark execution: false"
    assert html =~ "Automatic promotion: false"
    assert html =~ "controlkeel obs loop"
  end
end
