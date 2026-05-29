defmodule ControlKeelWeb.P4MarketingTest do
  use ControlKeelWeb.ConnCase, async: true

  describe "marketing home page" do
    test "anonymous cloud visitor sees marketing hero", %{conn: conn} do
      # Set runtime mode to cloud for this test
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "The control tower for"
      assert conn.resp_body =~ "AI-built software"

      Application.put_env(:controlkeel, :runtime_mode, original)
    end

    test "anonymous cloud visitor sees feature cards", %{conn: conn} do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "Governance by default"
      assert conn.resp_body =~ "Cost control"
      assert conn.resp_body =~ "Agent-agnostic"

      Application.put_env(:controlkeel, :runtime_mode, original)
    end

    test "anonymous cloud visitor sees how it works steps", %{conn: conn} do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "How it works"
      assert conn.resp_body =~ "Define intent"
      assert conn.resp_body =~ "Ship with confidence"

      Application.put_env(:controlkeel, :runtime_mode, original)
    end

    test "anonymous cloud visitor sees CTAs", %{conn: conn} do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      conn = get(conn, ~p"/")
      assert conn.resp_body =~ "Get started free"
      assert conn.resp_body =~ "View pricing"

      Application.put_env(:controlkeel, :runtime_mode, original)
    end

    test "anonymous cloud visitor does not see dashboard", %{conn: conn} do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      conn = get(conn, ~p"/")
      refute conn.resp_body =~ "Governed Delivery Monitor"

      Application.put_env(:controlkeel, :runtime_mode, original)
    end
  end
end
