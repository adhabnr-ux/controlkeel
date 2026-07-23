defmodule ControlKeel.Autonomy.DispatcherTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  alias ControlKeel.Autonomy.Dispatcher
  alias ControlKeel.Autonomy.Job
  alias ControlKeel.Mission
  alias ControlKeel.Mission.SessionTranscript
  alias ControlKeel.Repo

  setup do
    org = org_fixture()
    ws = workspace_fixture(%{org_id: org.id})

    {:ok, job} =
      Job.from_config(%{
        name: :test_job,
        interval_ms: 1_000,
        title: "Test job",
        task: "Do the test thing."
      })

    {:ok, org: org, workspace: ws, job: job}
  end

  describe "dispatch/2 dry_run" do
    test "returns the plan without recording anything", %{job: job, workspace: ws} do
      ws_id = ws.id

      assert {:ok, %{dry_run: true, job: "test_job", workspace_id: ^ws_id, launched: false}} =
               Dispatcher.dispatch(job, workspace_id: ws.id, dry_run: true)

      # Nothing was recorded.
      assert Mission.list_session_events(-1) == []
    end
  end

  describe "dispatch/2 wake-up (no launcher)" do
    test "creates a session + task + autonomy.wake event", %{job: job, workspace: ws} do
      assert {:ok, %{session_id: sid, task_id: tid, launched: nil}} =
               Dispatcher.dispatch(job, workspace_id: ws.id)

      assert %{title: "[autonomy] Test job", objective: "Do the test thing."} =
               Mission.get_session(sid)

      events = SessionTranscript.recent_events(sid, limit: 5)
      assert Enum.any?(events, &(&1["event_type"] == "autonomy.wake"))
      assert Enum.any?(events, &(&1["actor"] == "autonomy.scheduler"))

      # The task is bound to the wake-up session.
      assert %{} = Mission.get_task(tid)
    end

    test "requires explicit workspace binding", %{job: job} do
      assert {:error, :workspace_id_required} = Dispatcher.dispatch(job, [])
    end
  end

  describe "dispatch/2 with launcher" do
    test "records the launcher result when shell is enabled", %{workspace: ws} do
      restore_env(fn ->
        System.put_env("CK_AUTONOMY_ALLOW_SHELL", "1")

        {:ok, job} =
          Job.from_config(%{
            name: :launching,
            interval_ms: 1,
            title: "Launch",
            task: "echo me",
            launcher: %{adapter: :shell, command: "echo", args: [:task]}
          })

        assert {:ok, %{session_id: sid, launched: %{exit_status: 0}}} =
                 Dispatcher.dispatch(job, workspace_id: ws.id)

        events = SessionTranscript.recent_events(sid, limit: 5)
        wake = Enum.find(events, &(&1["event_type"] == "autonomy.wake"))
        result = Enum.find(events, &(&1["event_type"] == "autonomy.launch.result"))

        assert wake["payload"]["phase"] == "prepared"
        assert result["payload"]["status"] == "completed"
        assert result["payload"]["exit_status"] == 0
        assert result["id"] > wake["id"]
      end)
    end

    test "records wake-up without launching when shell is disabled", %{workspace: ws} do
      restore_env(fn ->
        System.delete_env("CK_AUTONOMY_ALLOW_SHELL")

        {:ok, job} =
          Job.from_config(%{
            name: :gated,
            interval_ms: 1,
            title: "Gated",
            task: "echo me",
            launcher: %{adapter: :shell, command: "echo", args: [:task]}
          })

        assert {:ok, %{session_id: sid, launched: nil}} =
                 Dispatcher.dispatch(job, workspace_id: ws.id)

        result =
          sid
          |> SessionTranscript.recent_events(limit: 5)
          |> Enum.find(&(&1["event_type"] == "autonomy.launch.result"))

        assert result["payload"] == %{"status" => "skipped"}
      end)
    end

    test "records missing-binary failures as JSON-safe strings", %{workspace: ws} do
      restore_env(fn ->
        System.put_env("CK_AUTONOMY_ALLOW_SHELL", "1")

        {:ok, job} =
          Job.from_config(%{
            name: :missing,
            interval_ms: 1,
            title: "Missing",
            task: "run",
            launcher: %{adapter: :shell, command: "does-not-exist-xyz", args: [:task]}
          })

        assert {:ok, %{session_id: sid, launched: %{error: error}}} =
                 Dispatcher.dispatch(job, workspace_id: ws.id)

        assert is_binary(error)

        result =
          sid
          |> SessionTranscript.recent_events(limit: 5)
          |> Enum.find(&(&1["event_type"] == "autonomy.launch.result"))

        assert result["payload"]["status"] == "failed"
        assert is_binary(result["payload"]["error"])
      end)
    end
  end

  describe "dispatch/2 workspace resolution" do
    test "honours an explicit workspace_id even when it differs from the first", %{
      job: job,
      org: org
    } do
      other = workspace_fixture(%{org_id: org.id})

      assert {:ok, %{workspace_id: id}} = Dispatcher.dispatch(job, workspace_id: other.id)
      assert id == other.id
    end

    test "rejects a nonexistent workspace instead of falling back across tenants", %{job: job} do
      assert {:error, :workspace_not_found} = Dispatcher.dispatch(job, workspace_id: 999_999)
    end
  end

  describe "wake-up transaction" do
    test "rolls back session and task when the required wake event cannot persist", %{
      job: job,
      workspace: ws
    } do
      before_ids = Mission.list_sessions() |> Enum.map(& &1.id) |> MapSet.new()

      Repo.query!("""
      CREATE TEMP TRIGGER fail_autonomy_wake
      BEFORE INSERT ON session_events
      WHEN NEW.event_type = 'autonomy.wake'
      BEGIN
        SELECT RAISE(ABORT, 'forced wake event failure');
      END;
      """)

      assert {:error, {:wake_persistence_failed, _reason}} =
               Dispatcher.dispatch(job, workspace_id: ws.id)

      after_ids = Mission.list_sessions() |> Enum.map(& &1.id) |> MapSet.new()
      assert after_ids == before_ids

      Repo.query!("DROP TRIGGER fail_autonomy_wake")
    end
  end

  defp restore_env(fun) do
    prev = System.get_env("CK_AUTONOMY_ALLOW_SHELL")

    try do
      fun.()
    after
      if prev,
        do: System.put_env("CK_AUTONOMY_ALLOW_SHELL", prev),
        else: System.delete_env("CK_AUTONOMY_ALLOW_SHELL")
    end
  end
end
