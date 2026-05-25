defmodule ControlKeelWeb.PolicyStudioLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  test "renders policy packs and rule counts", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Policy Studio"
    assert html =~ "Active governance rules"
    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Active packs"
    assert html =~ "Total rules"
    assert html =~ "Blocking rules"
  end

  test "shows pack descriptions in plain language", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Always active"
    assert html =~ "Detects secrets"
    assert html =~ "budget"
  end

  test "shows empty session state when no sessions exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "No active sessions"
    assert html =~ "/start"
  end

  test "shows session budgets when sessions exist", %{conn: conn} do
    _session =
      session_fixture(%{title: "Budget Session", budget_cents: 10_000, spent_cents: 2_500})

    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Budget Session"
    assert html =~ "$100"
    assert html =~ "ck-pill-high"
  end

  test "shows baseline and software policy packs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Baseline — Secrets"
    assert html =~ "Software — Code hygiene"
    assert html =~ "block"
    assert html =~ "warn"
  end

  test "lists what gets blocked automatically from live pack data", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "What gets blocked automatically"
    # Dynamic blocking rules section shows rule count badge
    assert html =~ "Blocking rules"
    # At least one pack name appears in the blocking rules context
    assert html =~ "Baseline"
    # The section includes guidance text
    assert html =~ "Blocks stop execution"
  end
end
