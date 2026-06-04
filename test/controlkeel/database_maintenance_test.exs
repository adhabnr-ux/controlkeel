defmodule ControlKeel.DatabaseMaintenanceTest do
  use ControlKeel.DataCase

  alias ControlKeel.DatabaseMaintenance
  alias ControlKeel.Mission.SessionEvent
  alias ControlKeel.Repo

  describe "run_once/1" do
    test "prunes session events older than max age" do
      session = insert_session()

      # Insert an event with a timestamp 91 days ago via raw SQL
      cutoff = DateTime.utc_now() |> DateTime.add(-91 * 86400, :second)
      cutoff_str = DateTime.to_iso8601(cutoff)

      Repo.insert_all("session_events", [
        %{
          event_type: "test.old",
          actor: "agent",
          summary: "old event",
          body: "",
          payload: "{}",
          metadata: "{}",
          session_id: session.id,
          inserted_at: cutoff_str,
          updated_at: cutoff_str
        }
      ])

      # Run maintenance with 90-day max age
      assert {:ok, %{events_pruned: 1}} = DatabaseMaintenance.run_once(event_max_age_days: 90)
    end

    test "keeps events within max age" do
      session = insert_session()

      attrs = %{
        event_type: "test.recent",
        actor: "agent",
        summary: "recent event",
        payload: %{},
        metadata: %{},
        session_id: session.id
      }

      {:ok, _event} = %SessionEvent{} |> SessionEvent.changeset(attrs) |> Repo.insert()

      assert {:ok, %{events_pruned: 0}} = DatabaseMaintenance.run_once(event_max_age_days: 90)
    end

    test "returns vacuumed status" do
      {:ok, result} = DatabaseMaintenance.run_once(event_max_age_days: 90, vacuum_enabled: false)
      assert result.vacuumed == false
    end

    test "does not run vacuum when nothing was pruned" do
      assert {:ok, %{events_pruned: 0, vacuumed: false}} =
               DatabaseMaintenance.run_once(event_max_age_days: 90, vacuum_enabled: true)
    end
  end

  describe "policy/0" do
    test "returns policy map with expected keys" do
      policy = DatabaseMaintenance.policy()
      assert Map.has_key?(policy, :enabled)
      assert Map.has_key?(policy, :session_events)
      assert Map.has_key?(policy, :sqlite)
      assert policy.sqlite.mode == "full"
      refute Map.has_key?(policy.sqlite, :incremental)
    end
  end

  import ControlKeel.MissionFixtures

  defp insert_session do
    session_fixture()
  end
end
