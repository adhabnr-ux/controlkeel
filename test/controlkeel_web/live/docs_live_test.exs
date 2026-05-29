defmodule ControlKeelWeb.DocsLiveTest do
  use ControlKeelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "docs index" do
    test "renders docs index without auth", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/docs")
      assert html =~ "Documentation"
      assert html =~ "Everything you need to know about ControlKeel"
    end

    test "lists available docs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/docs")
      assert html =~ "Getting Started"
    end

    test "hides internal docs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/docs")
      refute html =~ "CLOUD_READINESS"
      refute html =~ "cloud-parity-matrix"
      refute html =~ "TOKEN_OPTIMIZATION_GUIDE"
    end
  end

  describe "docs show" do
    test "renders a doc by name", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")
      assert conn.status == 200
      assert conn.resp_body =~ "← All docs"
    end

    test "shows doc title", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")
      assert conn.resp_body =~ "Getting Started"
    end

    test "renders markdown content", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started")
      assert conn.resp_body =~ "ControlKeel"
    end

    test "rejects path traversal via 404", %{conn: conn} do
      conn = get(conn, "/docs/../mix.exs")
      assert conn.status == 404
    end
  end
end
