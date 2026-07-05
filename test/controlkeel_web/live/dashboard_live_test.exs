defmodule ControlKeelWeb.DashboardLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the controlkeel dashboard", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Agent Control Plane"
    assert html =~ "Dashboard"
    assert html =~ "Benchmark Catch Rate"
    assert html =~ "Proof Coverage"
    assert html =~ "Deploy Ready Rate"
    assert html =~ "Delivery Flow"
    assert html =~ "Recent Missions"
    assert html =~ "Provider and Autonomy Status"
    assert html =~ "Provider and bootstrap status"
    assert html =~ "Active provider"
    assert html =~ "ACP registry cache"
    assert html =~ "Cache status"
    assert html =~ "skills-provider-status"
    assert html =~ "skills-registry-status"
    assert html =~ "Signal Preview"
    assert html =~ "New Mission"
    assert html =~ "Docs"
    assert html =~ "GitHub"
  end
end
