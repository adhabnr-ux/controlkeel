defmodule ControlKeelWeb.P4MarketingTest do
  use ControlKeelWeb.ConnCase, async: false

  describe "marketing home page" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, original) end)
      :ok
    end

    test "anonymous cloud visitor sees marketing hero", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "The control tower for"
      assert conn.resp_body =~ "AI-built software"
    end

    test "anonymous cloud visitor sees feature cards", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "Governance by default"
      assert conn.resp_body =~ "Cost control"
      assert conn.resp_body =~ "Agent-agnostic"
    end

    test "anonymous cloud visitor sees how it works steps", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "How it works"
      assert conn.resp_body =~ "Define intent"
      assert conn.resp_body =~ "Ship with confidence"
    end

    test "anonymous cloud visitor sees CTAs", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "Get started free"
      assert conn.resp_body =~ "View pricing"
    end

    test "anonymous cloud visitor does not see dashboard", %{conn: conn} do
      conn = get(conn, ~p"/")
      refute conn.resp_body =~ "Governed Delivery Monitor"
    end
  end
end
