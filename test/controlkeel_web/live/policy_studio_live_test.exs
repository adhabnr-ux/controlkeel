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

  test "shows empty policy-sets state when none exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "No custom policy sets yet"
  end

  test "lists policy sets with status, rule count, and workspace assignments", %{conn: conn} do
    {:ok, set} =
      ControlKeel.Platform.create_policy_set(%{
        "name" => "no-rm-rf",
        "description" => "Block destructive deletes",
        "rules" => [
          %{
            "id" => "shell.destructive_rm_rf",
            "category" => "security",
            "severity" => "critical",
            "action" => "block",
            "plain_message" => "blocked",
            "matcher" => %{"type" => "regex", "patterns" => ["rm -rf"]}
          }
        ]
      })

    {:ok, workspace} = Accounts.create_org(%{name: "Org A", slug: "test-org-a"})
    ws = workspace_fixture(%{org_id: workspace.id})
    {:ok, _assignment} = ControlKeel.Platform.apply_policy_set(ws.id, set.id, %{precedence: 10})

    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "no-rm-rf"
    assert html =~ "active"
    assert html =~ "1 rules"
    assert html =~ "Block destructive deletes"
    assert html =~ "workspace ##{ws.id}"
    assert html =~ "precedence 10"
  end

  test "block count badge shows destructive class", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "bg-destructive/15"
  end

  test "warn rules show warning class when pack is expanded", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(element(view, "button[phx-value-name=\"software\"]"))

    assert render(view) =~ "var(--ck-warning)"
  end

  test "renders pack labels for known domain packs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Software"
  end
end
