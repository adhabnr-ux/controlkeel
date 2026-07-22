defmodule ControlKeel.Autonomy.DispatcherTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  alias ControlKeel.Autonomy.Dispatcher
  alias ControlKeel.Autonomy.Job
  alias ControlKeel.Mission
  alias ControlKeel.Mission.SessionTranscript

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

      assert {:ok, %{dry_run: true, job: :test_job, workspace_id: ^ws_id, launched: false}} =
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

    test "falls back to the first workspace when none is given", %{job: job, workspace: ws} do
      assert {:ok, %{workspace_id: id}} = Dispatcher.dispatch(job, [])
      assert id == ws.id
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

        assert {:ok, %{launched: %{exit_status: 0}}} =
                 Dispatcher.dispatch(job, workspace_id: ws.id)
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

        assert {:ok, %{launched: nil}} = Dispatcher.dispatch(job, workspace_id: ws.id)
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
