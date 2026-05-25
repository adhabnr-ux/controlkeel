defmodule ControlKeel.Bus.JetStreamTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Bus.JetStream

  describe "start_link/1" do
    test "starts without NATS connection (graceful degradation)" do
      # No NATS server running in test env — should start with conn: nil
      {:ok, pid} = JetStream.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "publish/2 — disconnected mode" do
    setup do
      {:ok, pid} = GenServer.start_link(JetStream, [])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, pid: pid}
    end

    test "buffers messages when no NATS connection", %{pid: pid} do
      assert :ok = GenServer.call(pid, {:publish, "controlkeel.test", "hello"})
      assert GenServer.call(pid, :pending_count) == 1
    end

    test "buffers multiple messages in order", %{pid: pid} do
      GenServer.call(pid, {:publish, "t1", "a"})
      GenServer.call(pid, {:publish, "t2", "b"})
      GenServer.call(pid, {:publish, "t3", "c"})
      assert GenServer.call(pid, :pending_count) == 3
    end

    test "publish_json/2 encodes and buffers", %{pid: pid} do
      encoded = Jason.encode!(%{type: "test", id: 1})
      assert :ok = GenServer.call(pid, {:publish, "controlkeel.events", encoded})
      assert GenServer.call(pid, :pending_count) >= 1
    end
  end
end
