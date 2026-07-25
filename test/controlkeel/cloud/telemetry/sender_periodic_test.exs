defmodule ControlKeel.Cloud.Telemetry.Sender.PeriodicTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.Telemetry.Sender.Periodic
  alias ControlKeel.Cloud.Telemetry.Config
  alias ControlKeel.Cloud.Telemetry.Envelope
  alias ControlKeel.Cloud.Telemetry.Queue
  alias ControlKeel.Cloud.Workspace.Identity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-periodic-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    previous_endpoint = Application.get_env(:controlkeel, :cloud_telemetry_endpoint)
    Application.delete_env(:controlkeel, :cloud_telemetry_endpoint)
    previous_http = Application.get_env(:controlkeel, :cloud_sender_http_module)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      if previous_endpoint do
        Application.put_env(:controlkeel, :cloud_telemetry_endpoint, previous_endpoint)
      else
        Application.delete_env(:controlkeel, :cloud_telemetry_endpoint)
      end

      if previous_http do
        Application.put_env(:controlkeel, :cloud_sender_http_module, previous_http)
      else
        Application.delete_env(:controlkeel, :cloud_sender_http_module)
      end

      Application.delete_env(:controlkeel, :fake_http_handler)

      File.rm_rf!(tmp_home)
    end)

    :ok
  end

  describe "status/0" do
    test "returns :not_running when no GenServer is started" do
      assert Periodic.status() == :not_running
    end
  end

  describe "flush_now/0" do
    test "drives a single flush when manually invoked" do
      {:ok, _identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      enqueue("heartbeat", %{})

      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")

      install_http(fn _url, _opts -> {:ok, %{status: 200}} end)

      {:ok, pid} = Periodic.start_link(interval_ms: 600_000)
      allow_sandbox(pid)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, :sent, 1} = Periodic.flush_now()
      assert Queue.pending_count() == 0

      status = Periodic.status()
      assert match?({:ok, :sent, 1}, status.last_outcome)
      assert %DateTime{} = status.last_run_at
      assert status.consecutive_failures == 0
    end

    test "is a no-op when endpoint is unconfigured" do
      install_forbidden_http()

      {:ok, pid} = Periodic.start_link(interval_ms: 600_000)
      allow_sandbox(pid)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      assert {:ok, :no_endpoint, 0} = Periodic.flush_now()
      assert Periodic.status().consecutive_failures == 0
    end
  end

  describe "backoff behaviour" do
    test "consecutive_failures grows and interval doubles up to the cap" do
      {:ok, _identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      enqueue("heartbeat", %{})

      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      install_http(fn _url, _opts -> {:ok, %{status: 500}} end)

      {:ok, pid} =
        Periodic.start_link(
          interval_ms: 600_000,
          backoff_initial_ms: 100,
          backoff_max_ms: 800
        )

      allow_sandbox(pid)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      _ = Periodic.flush_now()
      assert Periodic.status().consecutive_failures == 1
      assert Periodic.status().next_interval_ms == 100

      enqueue("heartbeat", %{"n" => 2})
      _ = Periodic.flush_now()
      assert Periodic.status().consecutive_failures == 2
      assert Periodic.status().next_interval_ms == 200

      enqueue("heartbeat", %{"n" => 3})
      _ = Periodic.flush_now()
      assert Periodic.status().next_interval_ms == 400

      enqueue("heartbeat", %{"n" => 4})
      _ = Periodic.flush_now()
      assert Periodic.status().next_interval_ms == 800

      enqueue("heartbeat", %{"n" => 5})
      _ = Periodic.flush_now()
      # capped at backoff_max_ms
      assert Periodic.status().next_interval_ms == 800
    end

    test "a successful flush resets the backoff" do
      {:ok, _identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      enqueue("heartbeat", %{})

      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      install_http(fn _url, _opts -> {:ok, %{status: 503}} end)

      {:ok, pid} =
        Periodic.start_link(
          interval_ms: 12_345,
          backoff_initial_ms: 100
        )

      allow_sandbox(pid)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      _ = Periodic.flush_now()
      assert Periodic.status().consecutive_failures == 1

      install_http(fn _url, _opts -> {:ok, %{status: 200}} end)
      enqueue("heartbeat", %{"x" => 1})
      _ = Periodic.flush_now()

      status = Periodic.status()
      assert status.consecutive_failures == 0
      assert status.next_interval_ms == 12_345
    end
  end

  describe "automatic ticking" do
    test "fires :tick on the configured interval" do
      {:ok, _identity, :created} = Identity.ensure()
      {:ok, _state} = Config.enable(:governance)
      enqueue("heartbeat", %{})

      Application.put_env(:controlkeel, :cloud_telemetry_endpoint, "https://cloud.example/v1")
      install_http(fn _url, _opts -> {:ok, %{status: 200}} end)

      {:ok, pid} = Periodic.start_link(interval_ms: 50)
      allow_sandbox(pid)
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

      # Allow at least one tick to fire automatically.
      :ok = wait_until(fn -> Queue.pending_count() == 0 end, 1_000)

      status = Periodic.status()
      assert match?({:ok, :sent, _}, status.last_outcome)
    end
  end

  defp enqueue(kind, payload) do
    {:ok, envelope} = Envelope.build(kind, payload)
    {:ok, :enqueued, _} = Queue.enqueue(envelope)
  end

  defp install_http(handler) do
    Application.put_env(:controlkeel, :cloud_sender_http_module, __MODULE__.FakeHTTP)
    Application.put_env(:controlkeel, :fake_http_handler, handler)
  end

  defp install_forbidden_http do
    Application.put_env(:controlkeel, :cloud_sender_http_module, __MODULE__.ForbiddenHTTP)
  end

  defp allow_sandbox(pid) do
    Ecto.Adapters.SQL.Sandbox.allow(ControlKeel.Repo.Local, self(), pid)
  end

  defp wait_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        :timeout
      else
        Process.sleep(25)
        do_wait_until(fun, deadline)
      end
    end
  end

  defmodule FakeHTTP do
    def post(url, opts) do
      handler =
        Application.get_env(:controlkeel, :fake_http_handler) ||
          fn _, _ -> {:ok, %{status: 200}} end

      handler.(url, opts)
    end
  end

  defmodule ForbiddenHTTP do
    def post(_url, _opts), do: raise("HTTP must not be called when endpoint is nil")
  end
end
