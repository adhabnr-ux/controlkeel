defmodule ControlKeelWeb.PolicyStudioLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts

  test "renders policy packs with stats cards", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Policy Studio"
    assert html =~ "Active packs"
    assert html =~ "Total rules"
    assert html =~ "Blocking rules"
  end

  test "toggle_pack ignores unknown pack names", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    before_click = render(view)
    render_click(view, "toggle_pack", %{"name" => "not-a-real-pack"})

    assert render(view) == before_click
  end

  test "toggle_pack expands and collapses baseline pack", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    trigger = element(view, "button[phx-value-name=\"baseline\"]")
    render_click(trigger)

    assert render(view) =~ "Detects secrets, injection, and XSS"

    render_click(trigger)

    refute render(view) =~ "Detects secrets, injection, and XSS"
  end

  test "shows empty tool-policies state when no org_id is present", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "All workspaces inherit global tool access"
  end

  test "shows workspace tool policies when org has non-inherit policies", %{conn: conn} do
    {:ok, org} = Accounts.create_org(%{name: "Test Org", slug: "test-org-tool"})
    workspace = workspace_fixture(%{org_id: org.id})

    Accounts.set_workspace_tool_policy(workspace.id, "allowlist", ["file_read", "bash"])

    conn = Plug.Test.init_test_session(conn, %{"current_org_id" => org.id})

    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ workspace.name
    assert html =~ "allowlist"
    assert html =~ "file_read"
    assert html =~ "bash"
  end

  test "block count badge shows bg-red-500/15 class", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "bg-red-500/15"
  end

  test "warn rules show yellow class when pack is expanded", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(element(view, "button[phx-value-name=\"software\"]"))

    assert render(view) =~ "yellow-300"
  end

  test "renders pack labels for known domain packs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Software"
  end
end
