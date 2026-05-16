defmodule ControlKeel.Budget.SpendAlertsTest do
  use ControlKeel.DataCase

  alias ControlKeel.Budget.SpendAlerts
  import ControlKeel.MissionFixtures

  setup do
    start_supervised!({SpendAlerts, auto_check: false})
    :ok
  end

  test "check_session returns no alerts for healthy session" do
    session =
      session_fixture(%{budget_cents: 10_000, daily_budget_cents: 5_000, spent_cents: 100})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert alerts == []
  end

  test "check_session fires info alert at 50% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 500})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_info))
  end

  test "check_session fires warning at 80% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 800})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_warning))
  end

  test "check_session fires critical at 95% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 950})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_critical))
  end

  test "check_session fires exceeded at 100% budget" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 1_000})

    {:ok, alerts} = SpendAlerts.check_session(session.id)
    assert Enum.any?(alerts, &(&1.type == :budget_exceeded))
  end

  test "check_session returns ok for unknown session" do
    assert {:ok, []} = SpendAlerts.check_session(999_999_999)
  end

  test "get_alerts returns stored alerts" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 950})

    SpendAlerts.check_session(session.id)
    assert {:ok, alerts} = SpendAlerts.get_alerts(session.id)
    assert length(alerts) > 0
  end

  test "register_callback stores callback function" do
    assert :ok = SpendAlerts.register_callback(fn _alert -> :ok end)
  end

  test "check_interaction_spike stores spike alerts for a session" do
    session = session_fixture()

    assert {:spike, alert} = SpendAlerts.check_interaction_spike(session.id, 450, 100)
    assert alert.type == :interaction_cost_spike
    assert alert.severity == :medium
    assert alert.ratio == 4.5

    assert {:ok, alerts} = SpendAlerts.get_alerts(session.id)
    assert Enum.any?(alerts, &(&1.type == :interaction_cost_spike))
  end

  test "check_interaction_spike returns normal below threshold or invalid baseline" do
    assert {:ok, :normal} = SpendAlerts.check_interaction_spike(123, 250, 100)
    assert {:ok, :normal} = SpendAlerts.check_interaction_spike(123, 250, 0)
  end

  test "check_interaction_spike fires registered callbacks" do
    test_pid = self()

    assert :ok =
             SpendAlerts.register_callback(fn alert -> send(test_pid, {:spike_alert, alert}) end)

    assert {:spike, alert} = SpendAlerts.check_interaction_spike(123, 900, 100)

    assert_receive {:spike_alert, ^alert}
  end

  test "alerts include budget context" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 500, spent_cents: 800})

    {:ok, [alert | _]} = SpendAlerts.check_session(session.id)
    assert alert.session_id == session.id
    assert alert.budget_cents == 1_000
    assert alert.spent_cents == 800
  end
end
