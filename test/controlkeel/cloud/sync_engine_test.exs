defmodule ControlKeel.Cloud.SyncEngineTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.SyncEngine
  alias ControlKeel.Cloud.Workspace.Identity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-sync-engine-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, _identity, :created} = Identity.ensure()

    # Ensure SyncEngine is started under test supervision
    sync_pid = Process.whereis(SyncEngine)

    if sync_pid && Process.alive?(sync_pid) do
      :ok
    else
      {:ok, _pid} = start_supervised({SyncEngine, [interval_ms: 60_000]})
    end

    :ok
  end

  describe "init/1 — dormant mode" do
    test "stays dormant when no cloud_sync_endpoint configured" do
      # Clear any endpoint
      previous = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, nil)

      on_exit(fn ->
        if previous do
          Application.put_env(:controlkeel, :cloud_sync_endpoint, previous)
        else
          Application.delete_env(:controlkeel, :cloud_sync_endpoint)
        end
      end)

      # SyncEngine should start without error even with no endpoint
      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      assert state.endpoint == nil
      GenServer.stop(pid, :normal)
    end
  end

  describe "force_sync/0" do
    test "returns not_configured when endpoint is missing" do
      result = SyncEngine.force_sync()
      assert {:error, :not_configured} == result
    end

    test "returns already_syncing when concurrent sync attempted" do
      # Start a dedicated engine
      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)

      # Mark as syncing
      :sys.replace_state(pid, fn state -> %{state | syncing: true} end)

      result = GenServer.call(pid, :sync, 60_000)
      assert {:error, :already_syncing} == result

      GenServer.stop(pid, :normal)
    end
  end

  describe "endpoint construction" do
    test "engine starts with nil endpoint when not configured" do
      previous = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      Application.delete_env(:controlkeel, :cloud_sync_endpoint)

      on_exit(fn ->
        if previous do
          Application.put_env(:controlkeel, :cloud_sync_endpoint, previous)
        end
      end)

      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      assert state.endpoint == nil
      GenServer.stop(pid, :normal)
    end

    test "engine resolves endpoint URL with trailing slash" do
      previous = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://cloud.example.com/")

      on_exit(fn ->
        if previous do
          Application.put_env(:controlkeel, :cloud_sync_endpoint, previous)
        else
          Application.delete_env(:controlkeel, :cloud_sync_endpoint)
        end
      end)

      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      # Endpoint should end with /cloud/v1/sync (no trailing slash)
      assert state.endpoint == "https://cloud.example.com/cloud/v1/sync"
      GenServer.stop(pid, :normal)
    end

    test "engine resolves endpoint URL without trailing slash" do
      previous = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://cloud.example.com")

      on_exit(fn ->
        if previous do
          Application.put_env(:controlkeel, :cloud_sync_endpoint, previous)
        else
          Application.delete_env(:controlkeel, :cloud_sync_endpoint)
        end
      end)

      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      assert state.endpoint == "https://cloud.example.com/cloud/v1/sync"
      GenServer.stop(pid, :normal)
    end

    test "self-hosted mode refuses the canonical SaaS endpoint" do
      previous_mode = Application.get_env(:controlkeel, :runtime_mode)
      previous_endpoint = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      previous_env = System.get_env("CONTROLKEEL_RUNTIME_MODE")

      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://controlkeel.com")
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")

      on_exit(fn ->
        if previous_mode,
          do: Application.put_env(:controlkeel, :runtime_mode, previous_mode),
          else: Application.delete_env(:controlkeel, :runtime_mode)

        if previous_endpoint,
          do: Application.put_env(:controlkeel, :cloud_sync_endpoint, previous_endpoint),
          else: Application.delete_env(:controlkeel, :cloud_sync_endpoint)

        if previous_env,
          do: System.put_env("CONTROLKEEL_RUNTIME_MODE", previous_env),
          else: System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      end)

      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      assert state.endpoint == nil
      assert {:error, :not_configured} = SyncEngine.force_sync(pid)
      GenServer.stop(pid, :normal)
    end

    test "cloud mode refuses a self-host endpoint" do
      previous_mode = Application.get_env(:controlkeel, :runtime_mode)
      previous_endpoint = Application.get_env(:controlkeel, :cloud_sync_endpoint)
      previous_env = System.get_env("CONTROLKEEL_RUNTIME_MODE")

      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://ck.example.com")
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")

      on_exit(fn ->
        if previous_mode,
          do: Application.put_env(:controlkeel, :runtime_mode, previous_mode),
          else: Application.delete_env(:controlkeel, :runtime_mode)

        if previous_endpoint,
          do: Application.put_env(:controlkeel, :cloud_sync_endpoint, previous_endpoint),
          else: Application.delete_env(:controlkeel, :cloud_sync_endpoint)

        if previous_env,
          do: System.put_env("CONTROLKEEL_RUNTIME_MODE", previous_env),
          else: System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      end)

      {:ok, pid} = GenServer.start(SyncEngine, interval_ms: 60_000)
      state = :sys.get_state(pid)
      assert state.endpoint == nil
      assert {:error, :not_configured} = SyncEngine.force_sync(pid)
      GenServer.stop(pid, :normal)
    end
  end
end
