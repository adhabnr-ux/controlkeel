defmodule ControlKeelWeb.PricingLiveTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders pricing page without auth", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "Simple, transparent pricing"
  end

  test "shows all three tiers", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "Free"
    assert html =~ "Pro"
    assert html =~ "Enterprise"
  end

  test "shows Pro pricing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "$29"
    assert html =~ "/seat/mo"
  end

  test "Free tier includes local governance features", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "Unlimited local projects"
    assert html =~ "Policy-as-code governance"
  end

  test "Pro tier includes cloud sync", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "Cloud sync"
    assert html =~ "Team collaboration"
  end

  test "Enterprise tier includes SSO", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "SAML / SSO"
    assert html =~ "Audit log export"
  end

  test "CTAs link to signup or sales", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/pricing")
    assert html =~ "/signup"
    assert html =~ "sales@controlkeel.com"
  end
end
