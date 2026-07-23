defmodule ControlKeel.Autonomy.Scheduler do
  @moduledoc """
  Governed, BEAM-native autonomy scheduler.

  Fires configured `ControlKeel.Autonomy.Job`s on a timer and dispatches each
  through `ControlKeel.Autonomy.Dispatcher`, producing a governed wake-up
  (session + task + audit event) and optionally launching an agent.

  This is ControlKeel's answer to cron-driven autonomy: an external scheduler
  (gumclaw's model) becomes a governed heartbeat that records every wake-up.

  ## Configuration

      config :controlkeel,
        autonomy: [
          enabled: true,
          allow_shell: false,
          workspace_id: 1,
          jobs: [
            %{name: :daily_triage, interval_ms: :timer.hours(6),
              title: "Triage", task: "Triage open support tickets."}
          ]
        ]

  Enabled via `CK_AUTONOMY_SCHEDULER` env var or `autonomy: [enabled: true]`.
  Never starts inside an MCP stdio server process.
  """

  use GenServer

  require Logger

  alias ControlKeel.Autonomy.Dispatcher
  alias ControlKeel.Autonomy.Job

  @task_supervisor ControlKeel.Autonomy.TaskSupervisor

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Whether the autonomy scheduler is explicitly enabled."
  def enabled? do
    env_enabled?() or config_enabled?()
  end

  @doc "Parsed configured jobs, or `[]` when none/invalid (errors are logged)."
  def jobs do
    case Job.from_config_all(config_jobs()) do
      {:ok, jobs} ->
        jobs

      {:error, reason} ->
        Logger.warning("[autonomy] job config invalid: #{inspect(reason)}")
        []
    end
  end

  @doc "Workspace id resolved from config, or nil."
  def workspace_id do
    autonomy_config() |> Keyword.get(:workspace_id)
  end

  @doc """
  Fire a single job by name now, regardless of its timer. Safe to call without
  the GenServer running (used by `mix ck.autonomy run` and tests).

  Options: `:dry_run`, `:workspace_id`.
  """
  def run_once(name, opts \\ []) when is_atom(name) or is_binary(name) do
    opts = put_workspace_opt(opts)
    name = to_string(name)

    case Enum.find(jobs(), &(&1.name == name)) do
      nil -> {:error, {:unknown_job, name}}
      job -> Dispatcher.dispatch(job, opts)
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    case Job.from_config_all(config_jobs()) do
      {:ok, jobs} ->
        state = %{timers: arm_jobs(jobs), workspace_id: workspace_opt(opts), config_error: nil}
        {:ok, state}

      {:error, reason} ->
        Logger.error("[autonomy] invalid job config; scheduler started inert: #{inspect(reason)}")

        {:ok, %{timers: %{}, workspace_id: workspace_opt(opts), config_error: reason}}
    end
  end

  @impl true
  def handle_info({:fire, name}, state) do
    opts = workspace_opts(state)

    case Task.Supervisor.start_child(@task_supervisor, fn -> dispatch_and_log(name, opts) end) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[autonomy] could not start dispatch task for #{inspect(name)}: #{inspect(reason)}"
        )
    end

    {:noreply, rearm(name, state)}
  end

  defp dispatch_and_log(name, opts) do
    case run_once(name, opts) do
      {:ok, %{session_id: sid}} ->
        Logger.debug("[autonomy] job #{inspect(name)} fired -> session ##{sid}")

      {:error, reason} ->
        Logger.warning("[autonomy] job #{inspect(name)} failed: #{inspect(reason)}")
    end
  end

  defp rearm(name, %{timers: timers} = state) do
    case Enum.find(jobs(), &(&1.name == name)) do
      %Job{interval_ms: ms} ->
        %{state | timers: Map.put(timers, name, Process.send_after(self(), {:fire, name}, ms))}

      nil ->
        # Job removed from config mid-flight; leave disarmed.
        state
    end
  end

  defp arm_jobs(jobs) do
    Enum.reduce(jobs, %{}, fn job, acc ->
      Map.put(acc, job.name, arm_timer(job))
    end)
  end

  defp arm_timer(%Job{interval_ms: interval_ms, name: name}) do
    Process.send_after(self(), {:fire, name}, interval_ms)
  end

  defp workspace_opts(%{workspace_id: id}) when is_integer(id), do: [workspace_id: id]
  defp workspace_opts(_), do: []

  defp workspace_opt(opts) do
    Keyword.get(opts, :workspace_id) || workspace_id()
  end

  defp put_workspace_opt(opts) do
    if Keyword.has_key?(opts, :workspace_id) do
      opts
    else
      Keyword.put(opts, :workspace_id, workspace_id())
    end
  end

  defp env_enabled? do
    System.get_env("CK_AUTONOMY_SCHEDULER") in ~w(1 true TRUE yes YES)
  end

  defp config_enabled? do
    autonomy_config() |> Keyword.get(:enabled, false)
  end

  defp config_jobs do
    autonomy_config() |> Keyword.get(:jobs, [])
  end

  defp autonomy_config do
    Application.get_env(:controlkeel, :autonomy, [])
  end
end
