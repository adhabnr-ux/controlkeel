defmodule ControlKeelWeb.Plugs.CloudRateLimitTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ControlKeel.Cloud.RateLimiter
  alias ControlKeelWeb.Plugs.CloudRateLimit

  setup do
    previous = Application.get_env(:controlkeel, :cloud_rate_limit, %{})
    Application.put_env(:controlkeel, :cloud_rate_limit, %{burst: 2, refill_per_sec: 1})

    on_exit(fn ->
      Application.put_env(:controlkeel, :cloud_rate_limit, previous)
    end)

    RateLimiter.reset()
    :ok
  end

  defp conn_for(ws_id) do
    conn(:post, "/cloud/v1/sync/push")
    |> assign(:db_workspace_id, ws_id)
  end

  test "passes through when bucket has tokens" do
    conn = conn_for(:rand.uniform(1_000_000)) |> CloudRateLimit.call([])
    refute conn.halted
    assert conn.status == nil
  end

  test "returns 429 with Retry-After header when bucket is empty" do
    ws_id = :rand.uniform(1_000_000)

    # Drain the configured burst of 2
    _ = conn_for(ws_id) |> CloudRateLimit.call([])
    _ = conn_for(ws_id) |> CloudRateLimit.call([])
    blocked = conn_for(ws_id) |> CloudRateLimit.call([])

    assert blocked.halted
    assert blocked.status == 429
    [retry_after] = get_resp_header(blocked, "retry-after")
    assert String.to_integer(retry_after) >= 1

    body = Jason.decode!(blocked.resp_body)
    assert body["error"] == "rate_limited"
    assert body["retry_after"] >= 1
  end

  test "missing :db_workspace_id passes through (auth plug halts earlier)" do
    conn =
      conn(:post, "/cloud/v1/sync/push")
      |> CloudRateLimit.call([])

    refute conn.halted
  end

  test "separate workspaces are not rate-limited together" do
    ws_a = :rand.uniform(1_000_000)
    ws_b = :rand.uniform(1_000_000)

    _ = conn_for(ws_a) |> CloudRateLimit.call([])
    _ = conn_for(ws_a) |> CloudRateLimit.call([])
    blocked_a = conn_for(ws_a) |> CloudRateLimit.call([])
    assert blocked_a.status == 429

    ok_b = conn_for(ws_b) |> CloudRateLimit.call([])
    refute ok_b.halted
  end
end
