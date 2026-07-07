defmodule ControlKeel.MCP.DiscoveryTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Discovery

  test "stdio discovery is explicit unsupported instead of empty success" do
    assert {:error, {:unsupported_transport, :stdio}} =
             Discovery.discover("stdio:///tmp/example", transport: :stdio)
  end

  test "http discovery blocks loopback targets by default" do
    assert {:error, {:blocked_target, "localhost"}} =
             Discovery.discover("http://localhost:4000/mcp", transport: :http)
  end
end
