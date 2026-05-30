defmodule ControlKeel.Cloud.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.RateLimiter

  setup do
    previous = Application.get_env(:controlkeel, :cloud_rate_limit, %{})
    Application.put_env(:controlkeel, :cloud_rate_limit, %{burst: 3, refill_per_sec: 1})

    on_exit(fn ->
      Application.put_env(:controlkeel, :cloud_rate_limit, previous)
    end)

    RateLimiter.reset()
    :ok
  end

  test "allows the configured burst then rate-limits" do
    ws_id = :rand.uniform(1_000_000)

    assert :ok = RateLimiter.hit(ws_id)
    assert :ok = RateLimiter.hit(ws_id)
    assert :ok = RateLimiter.hit(ws_id)
    assert {:error, :rate_limited, retry_after} = RateLimiter.hit(ws_id)
    assert retry_after >= 1
  end

  test "different workspaces have independent buckets" do
    ws_a = :rand.uniform(1_000_000)
    ws_b = :rand.uniform(1_000_000)

    Enum.each(1..3, fn _ -> assert :ok = RateLimiter.hit(ws_a) end)
    assert {:error, :rate_limited, _} = RateLimiter.hit(ws_a)

    Enum.each(1..3, fn _ -> assert :ok = RateLimiter.hit(ws_b) end)
  end

  test "refills tokens over time" do
    ws_id = :rand.uniform(1_000_000)

    # Drain the bucket
    Enum.each(1..3, fn _ -> RateLimiter.hit(ws_id) end)
    assert {:error, :rate_limited, _} = RateLimiter.hit(ws_id)

    # Wait long enough to refill at least 1 token (1/sec)
    Process.sleep(1_100)

    assert :ok = RateLimiter.hit(ws_id)
  end

  test "reset/0 clears all buckets" do
    ws_id = :rand.uniform(1_000_000)

    Enum.each(1..3, fn _ -> RateLimiter.hit(ws_id) end)
    assert {:error, :rate_limited, _} = RateLimiter.hit(ws_id)

    RateLimiter.reset()

    assert :ok = RateLimiter.hit(ws_id)
  end

  test "respects per-call burst override" do
    ws_id = :rand.uniform(1_000_000)

    # Per-call burst of 1 — first hit succeeds, second is limited
    assert :ok = RateLimiter.hit(ws_id, burst: 1)
    assert {:error, :rate_limited, _} = RateLimiter.hit(ws_id, burst: 1)
  end
end
