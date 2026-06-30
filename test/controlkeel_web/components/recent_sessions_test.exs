defmodule ControlKeelWeb.RecentSessionsTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeelWeb.RecentSessions

  test "renders empty state when no runs" do
    html = render_component(&RecentSessions.session_observability_section/1, runs: [])
    assert html =~ "Recent session runs"
    assert html =~ "No sessions available yet."
  end

  test "renders session list with health pills" do
    runs = [
      %{id: 1, title: "Session A", health: "red"},
      %{id: 2, title: "Session B", health: "green"}
    ]

    html = render_component(&RecentSessions.session_observability_section/1, runs: runs)
    assert html =~ "Session A"
    assert html =~ "Session B"
    assert html =~ "/observability/sessions/1"
    assert html =~ "/observability/sessions/2"
    refute html =~ "No sessions available yet."
  end
end
