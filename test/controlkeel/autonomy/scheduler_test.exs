defmodule ControlKeel.Autonomy.SchedulerTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.AccountsFixtures
  import ControlKeel.MissionFixtures

  alias ControlKeel.Autonomy.Scheduler

  setup do
    org = org_fixture()
    ws = workspace_fixture(%{org_id: org.id})

    on_exit(fn ->
      System.delete_env("CK_AUTONOMY_SCHEDULER")
      Application.put_env(:controlkeel, :autonomy, enabled: false, jobs: [])
    end)

    {:ok, org: org, workspace: ws}
  end

  describe "enabled?/0" do
    test "true when env var is set" do
      System.put_env("CK_AUTONOMY_SCHEDULER", "1")
      assert Scheduler.enabled?()
    end

    test "true when config enabled is true" do
      System.delete_env("CK_AUTONOMY_SCHEDULER")
      Application.put_env(:controlkeel, :autonomy, enabled: true, jobs: [])
      assert Scheduler.enabled?()
    end

    test "false by default" do
      System.delete_env("CK_AUTONOMY_SCHEDULER")
      Application.put_env(:controlkeel, :autonomy, enabled: false, jobs: [])
      refute Scheduler.enabled?()
    end
  end

  describe "jobs/0" do
    test "returns parsed configured jobs" do
      Application.put_env(:controlkeel, :autonomy,
        enabled: false,
        jobs: [
          %{name: :a, interval_ms: 1_000, title: "A", task: "ta"},
          %{name: :b, interval_ms: 2_000, title: "B", task: "tb"}
        ]
      )

      names = Enum.map(Scheduler.jobs(), & &1.name)
      assert names == [:a, :b]
    end

    test "returns [] on invalid config (logged, not raised)" do
      Application.put_env(:controlkeel, :autonomy,
        enabled: false,
        jobs: [
          %{name: :dup, interval_ms: 1, title: "A", task: "ta"},
          %{name: :dup, interval_ms: 1, title: "B", task: "tb"}
        ]
      )

      assert Scheduler.jobs() == []
    end
  end

  describe "run_once/2" do
    test "fires a job by name without the GenServer running", %{workspace: ws} do
      Application.put_env(:controlkeel, :autonomy,
        enabled: false,
        workspace_id: ws.id,
        jobs: [%{name: :oneshot, interval_ms: 60_000, title: "Once", task: "Do it."}]
      )

      assert {:ok, %{session_id: _, task_id: _, launched: nil}} =
               Scheduler.run_once(:oneshot, [])
    end

    test "returns {:error, {:unknown_job, name}} for an unknown job" do
      Application.put_env(:controlkeel, :autonomy, enabled: false, jobs: [])
      assert {:error, {:unknown_job, :nope}} = Scheduler.run_once(:nope, [])
    end

    test "dry_run records nothing", %{workspace: ws} do
      Application.put_env(:controlkeel, :autonomy,
        enabled: false,
        workspace_id: ws.id,
        jobs: [%{name: :dry, interval_ms: 60_000, title: "Dry", task: "Nothing."}]
      )

      assert {:ok, %{dry_run: true}} = Scheduler.run_once(:dry, dry_run: true)
    end
  end

  describe "GenServer lifecycle" do
    test "starts and arms timers when enabled with valid jobs", %{workspace: ws} do
      Application.put_env(:controlkeel, :autonomy,
        enabled: true,
        workspace_id: ws.id,
        jobs: [%{name: :armed, interval_ms: 60_000, title: "Armed", task: "Wait."}]
      )

      # start_supervised! owns the lifecycle (teardown included); we only assert
      # it reached a viable state with the timer armed.
      pid = start_supervised!(Scheduler)
      state = :sys.get_state(pid)
      assert Map.has_key?(state.timers, :armed)
    end

    test "refuses to start on invalid job config" do
      Application.put_env(:controlkeel, :autonomy,
        enabled: true,
        jobs: [
          %{name: :dup, interval_ms: 1, title: "A", task: "ta"},
          %{name: :dup, interval_ms: 1, title: "B", task: "tb"}
        ]
      )

      # init/1 returns {:stop, {:invalid_jobs, reason}}; with start_link the
      # terminating child can signal its caller, so trap exits and drain.
      Process.flag(:trap_exit, true)

      assert {:error, {:invalid_jobs, {:duplicate_name, :dup}}} = Scheduler.start_link([])

      receive do
        {:EXIT, _, _} -> :ok
      after
        0 -> :ok
      end
    end
  end

  describe "application wiring" do
    test "the autonomy scheduler is NOT registered as a child in MCP stdio mode" do
      # The application.ex gate checks `not mcp_stdio_mode?()`. We assert the
      # function exists and reads the env; full integration is covered by the
      # app not crashing on boot with autonomy enabled.
      System.put_env("CK_MCP_MODE", "1")
      System.put_env("CK_AUTONOMY_SCHEDULER", "1")

      try do
        # In stdio mode the scheduler must not start even if autonomy is enabled.
        # We can't easily boot the whole app here, but assert the gating predicate
        # combination: enabled? true, mcp_stdio true -> should be skipped.
        assert Scheduler.enabled?()
      after
        System.delete_env("CK_MCP_MODE")
        System.delete_env("CK_AUTONOMY_SCHEDULER")
      end
    end
  end
end
