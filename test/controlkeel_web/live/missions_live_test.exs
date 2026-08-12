defmodule ControlKeelWeb.MissionsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "missions index shows the full session history", %{conn: conn} do
    workspace = workspace_fixture(%{name: "History Workspace"})

    for n <- 1..7 do
      session_fixture(%{workspace: workspace, title: "Session #{n}"})
    end

    {:ok, _view, html} = live(conn, ~p"/sessions")

    assert html =~ "Session 7"
    assert html =~ "Session 1"
  end
end
