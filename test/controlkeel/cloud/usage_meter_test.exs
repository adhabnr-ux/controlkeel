defmodule ControlKeel.Cloud.UsageMeterTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.UsageMeter

  setup do
    UsageMeter.reset_all()
    on_exit(fn -> UsageMeter.reset_all() end)
    :ok
  end

  test "records and retrieves daily spend" do
    org_id = :rand.uniform(1_000_000)

    assert UsageMeter.usage_today(org_id) == 0

    :ok = UsageMeter.record(org_id, 100, emit: false)
    :ok = UsageMeter.record(org_id, 50, emit: false)

    assert UsageMeter.usage_today(org_id) == 150
  end

  test "different orgs have independent buckets" do
    org_a = :rand.uniform(1_000_000)
    org_b = :rand.uniform(1_000_000)

    :ok = UsageMeter.record(org_a, 200, emit: false)
    :ok = UsageMeter.record(org_b, 300, emit: false)

    assert UsageMeter.usage_today(org_a) == 200
    assert UsageMeter.usage_today(org_b) == 300
  end

  test "usage_for_date targets a specific date" do
    org_id = :rand.uniform(1_000_000)
    yesterday = Date.add(Date.utc_today(), -1)

    :ok = UsageMeter.record(org_id, 100, date: yesterday, emit: false)
    :ok = UsageMeter.record(org_id, 50, emit: false)

    assert UsageMeter.usage_for_date(org_id, yesterday) == 100
    assert UsageMeter.usage_today(org_id) == 50
  end

  test "usage_range returns map across dates" do
    org_id = :rand.uniform(1_000_000)
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    :ok = UsageMeter.record(org_id, 100, date: yesterday, emit: false)
    :ok = UsageMeter.record(org_id, 50, emit: false)

    range = UsageMeter.usage_range(org_id, yesterday, today)
    assert range[yesterday] == 100
    assert range[today] == 50
  end

  test "usage_range total mode sums across dates" do
    org_id = :rand.uniform(1_000_000)
    today = Date.utc_today()
    yesterday = Date.add(today, -1)

    :ok = UsageMeter.record(org_id, 100, date: yesterday, emit: false)
    :ok = UsageMeter.record(org_id, 50, emit: false)

    assert UsageMeter.usage_range(org_id, yesterday, today, :total) == 150
  end

  test "reset/1 clears only the target org" do
    org_a = :rand.uniform(1_000_000)
    org_b = :rand.uniform(1_000_000)

    :ok = UsageMeter.record(org_a, 200, emit: false)
    :ok = UsageMeter.record(org_b, 300, emit: false)

    :ok = UsageMeter.reset(org_a)

    assert UsageMeter.usage_today(org_a) == 0
    assert UsageMeter.usage_today(org_b) == 300
  end

  test "reset_all/0 clears everything" do
    org_id = :rand.uniform(1_000_000)
    :ok = UsageMeter.record(org_id, 500, emit: false)

    :ok = UsageMeter.reset_all()
    assert UsageMeter.usage_today(org_id) == 0
  end
end
