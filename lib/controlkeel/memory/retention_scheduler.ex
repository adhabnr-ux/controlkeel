defmodule ControlKeel.Memory.RetentionScheduler do
  @moduledoc false

  use GenServer

  require Logger

  alias ControlKeel.Memory

  @default_interval_ms :timer.hours(24)

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

  @doc "Whether the scheduled retention sweeper is explicitly enabled."
  def enabled? do
    env_enabled?() or config_enabled?()
  end

  @doc "Retention policy advertised to operators; findings are preserved by default."
  def policy do
    memory = retention_config()

    %{
      memory: %{
        enabled: enabled?(),
        max_age_days: Keyword.get(memory, :max_age_days, 90),
        record_types: Keyword.get(memory, :record_types, ~w(task checkpoint budget))
      },
      findings: %{
        enabled: Keyword.get(memory, :findings_enabled, false),
        action: Keyword.get(memory, :findings_action, :preserve),
        note: "Findings are audit evidence and are never archived by the default scheduler."
      }
    }
  end

  @doc "Run one memory-retention sweep with the configured safe defaults."
  def run_once(opts \\ []) do
    opts = Keyword.merge(sweep_opts(), opts)
    Memory.archive_stale_records(opts)
  end

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, config_interval_ms())
    state = %{interval_ms: interval_ms}
    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    case run_once() do
      {:ok, %{archived: count}} ->
        Logger.debug("[memory_retention] archived #{count} stale record(s)")
    end

    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{interval_ms: interval_ms}) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule(_state), do: :ok

  defp sweep_opts do
    config = retention_config()

    [
      max_age_days: Keyword.get(config, :max_age_days, 90),
      record_types: Keyword.get(config, :record_types, ~w(task checkpoint budget))
    ]
  end

  defp config_enabled? do
    retention_config() |> Keyword.get(:enabled, false)
  end

  defp env_enabled? do
    System.get_env("CK_MEMORY_RETENTION_SCHEDULER") in ~w(1 true TRUE yes YES)
  end

  defp config_interval_ms do
    retention_config() |> Keyword.get(:interval_ms, @default_interval_ms)
  end

  defp retention_config do
    Application.get_env(:controlkeel, :memory_retention, [])
  end
end
