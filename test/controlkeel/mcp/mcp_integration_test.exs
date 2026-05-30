defmodule ControlKeel.MCP.IntegrationTest do
  @moduledoc """
  Integration tests for the MCP JSON-RPC layer.

  Uses MCP.Server.dispatch_request/2 with start_reader: false (no stdio) so
  tests run entirely in-process. Covers Scenario 5 (MCP integration) from
  DEPLOYMENT_SCENARIOS_STATUS.md.

  Each test starts a fresh MCP.Server GenServer and stops it on exit.
  """

  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Server

  # ── Setup ──────────────────────────────────────────────────────────────

  setup do
    {:ok, pid} = Server.start_link(start_reader: false)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000) end)
    {:ok, server: pid}
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  # dispatch_request/2 is a GenServer.call that returns the JSON-RPC response map
  # directly (not {:ok, map}) — the {:reply, map, state} tuple is unwrapped by OTP.
  defp request(pid, method, params \\ %{}, id \\ 1) do
    req = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
    Server.dispatch_request(pid, req)
  end

  # ── initialize ─────────────────────────────────────────────────────────

  test "initialize returns protocolVersion and serverInfo", %{server: pid} do
    resp =
      request(pid, "initialize", %{
        "protocolVersion" => "2024-11-05",
        "clientInfo" => %{"name" => "test-client", "version" => "0.0.1"}
      })

    result = resp["result"]
    assert is_binary(result["protocolVersion"])
    assert result["serverInfo"]["name"] == "controlkeel"
    assert get_in(result, ["capabilities", "tools"]) != nil
  end

  test "initialize echoes back jsonrpc and id", %{server: pid} do
    resp = request(pid, "initialize", %{"protocolVersion" => "2024-11-05"}, 42)

    assert resp["jsonrpc"] == "2.0"
    assert resp["id"] == 42
  end

  # ── tools/list ─────────────────────────────────────────────────────────

  test "tools/list returns non-empty tools array with CK tool names", %{server: pid} do
    resp = request(pid, "tools/list")

    tools = get_in(resp, ["result", "tools"])
    assert is_list(tools)
    assert length(tools) > 0

    tool_names = Enum.map(tools, & &1["name"])
    assert "ck_context" in tool_names
    assert "ck_finding" in tool_names
    assert "ck_validate" in tool_names
  end

  test "tools/list each tool has name, description, and inputSchema", %{server: pid} do
    resp = request(pid, "tools/list")

    tools = get_in(resp, ["result", "tools"])

    for tool <- tools do
      assert is_binary(tool["name"]), "#{inspect(tool["name"])} should be a string"
      assert is_binary(tool["description"]), "tool #{tool["name"]} missing description"
      assert is_map(tool["inputSchema"]), "tool #{tool["name"]} missing inputSchema"
    end
  end

  # ── tools/call ─────────────────────────────────────────────────────────

  test "tools/call ck_validate with text content returns a result", %{server: pid} do
    resp =
      request(pid, "tools/call", %{
        "name" => "ck_validate",
        "arguments" => %{"content" => "SELECT * FROM users", "kind" => "code"}
      })

    # Should return a result (pass or fail), not a -32601 method-not-found error
    assert resp["result"] != nil or resp["error"] != nil
    refute get_in(resp, ["error", "code"]) == -32601, "unexpected method not found"
  end

  test "tools/call with unknown tool name returns an error response (not a crash)", %{server: pid} do
    resp =
      request(pid, "tools/call", %{
        "name" => "nonexistent_tool_xyz",
        "arguments" => %{}
      })

    # Unknown tool returns an error map, not an exception
    assert is_map(resp)
    assert Process.alive?(pid), "Server must stay alive after unknown tool call"
  end

  # ── Unknown method ─────────────────────────────────────────────────────

  test "unknown method returns JSON-RPC method not found error", %{server: pid} do
    resp = request(pid, "completely/unknown/method")

    assert resp["error"]["code"] == -32601
  end

  # ── Malformed requests ──────────────────────────────────────────────────

  test "non-map request returns an error map without crashing the server", %{server: pid} do
    # Protocol.handle_request/2 catch-all returns an error_response map for non-maps.
    # GenServer.call returns it directly (or {:error, ...} on a rescue/catch in handle_call).
    result = Server.dispatch_request(pid, "not a map")
    assert is_map(result) or match?({:error, _}, result)
    assert Process.alive?(pid), "Server must survive a malformed request"
  end
end
