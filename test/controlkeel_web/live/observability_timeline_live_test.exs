defmodule ControlKeelWeb.ObservabilityTimelineLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission.SessionEvent
  alias ControlKeel.Repo

  test "timeline page renders recent session events", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _event} =
             %SessionEvent{}
             |> SessionEvent.changeset(%{
               session_id: session.id,
               event_type: "tool_call",
               actor: "agent",
               summary: "Ran a governed tool",
               body: "Tool details",
               payload: %{},
               metadata: %{}
             })
             |> Repo.insert()

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}/timeline")

    assert html =~ "Timeline"
    assert has_element?(view, "#observability-timeline-page")
    assert has_element?(view, "#observability-timeline-total")
    assert has_element?(view, "#observability-timeline-summary")
    assert has_element?(view, "#observability-timeline-events")
    assert html =~ "tool_call"
    assert html =~ "Ran a governed tool"
    assert html =~ "Tool details"
    assert html =~ "/observability/sessions/#{session.id}"
  end
end
