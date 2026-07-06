defmodule ControlKeel.Ops.Database do
  @moduledoc false

  use GenServer

  require Logger

  alias ControlKeel.Repo

  @default_interval_ms :timer.hours(24)
  @default_event_max_age_days 90
  @default_vacuum_enabled true

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

  @doc "Whether the database maintenance scheduler is enabled."
  def enabled? do
    env_enabled?() or config_enabled?()
  end

  @doc "Current maintenance policy."
  def policy do
    config = maintenance_config()

    %{
      enabled: enabled?(),
      session_events: %{
        max_age_days: Keyword.get(config, :event_max_age_days, @default_event_max_age_days),
        vacuum_after_prune: Keyword.get(config, :vacuum_enabled, @default_vacuum_enabled)
      },
      sqlite: %{
        vacuum_enabled: Keyword.get(config, :vacuum_enabled, @default_vacuum_enabled),
        mode: "full"
      }
    }
  end

  @doc "Run one maintenance sweep: prune old session events, then VACUUM if SQLite."
  def run_once(opts \\ []) do
    config = Keyword.merge(maintenance_config(), opts)
    max_age_days = Keyword.get(config, :event_max_age_days, @default_event_max_age_days)

    events_pruned = prune_old_session_events(max_age_days)

    vacuumed =
      if events_pruned > 0 and Keyword.get(config, :vacuum_enabled, @default_vacuum_enabled) do
        run_sqlite_vacuum(Keyword.get(config, :vacuum_timeout_ms, 30_000))
      else
        false
      end

    {:ok, %{events_pruned: events_pruned, vacuumed: vacuumed}}
  end

  # --- Session event pruning ---

  defp prune_old_session_events(max_age_days)
       when is_integer(max_age_days) and max_age_days > 0 do
    cutoff = DateTime.utc_now() |> DateTime.add(-max_age_days * 86400, :second)

    import Ecto.Query

    # Count first, then delete. SQLite does not support RETURNING with aggregates.
    count =
      from(e in "session_events",
        where: e.inserted_at < ^cutoff,
        select: count(e.id)
      )
      |> Repo.one() || 0

    if count > 0 do
      from(e in "session_events", where: e.inserted_at < ^cutoff)
      |> Repo.delete_all()

      Logger.info(
        "[db_maintenance] pruned #{count} session event(s) older than #{max_age_days} days"
      )
    end

    count
  rescue
    e ->
      Logger.warning("[db_maintenance] session event prune failed: #{Exception.message(e)}")
      0
  end

  defp prune_old_session_events(_), do: 0

  # --- SQLite VACUUM ---

  defp run_sqlite_vacuum(timeout_ms) do
    if sqlite_adapter?() do
      # VACUUM cannot run inside a transaction. Use the raw connection.
      db_path = database_path()

      if File.exists?(db_path) do
        # Use sqlite3 CLI if available, otherwise skip VACUUM
        case System.find_executable("sqlite3") do
          nil ->
            Logger.debug("[db_maintenance] sqlite3 CLI not found, skipping VACUUM")
            false

          sqlite3 ->
            case run_vacuum_cmd(sqlite3, db_path, timeout_ms) do
              {_, 0} ->
                Logger.info("[db_maintenance] SQLite VACUUM completed")
                true

              {output, _code} ->
                Logger.warning("[db_maintenance] SQLite VACUUM failed: #{String.trim(output)}")
                false

              :timeout ->
                Logger.warning("[db_maintenance] SQLite VACUUM timed out after #{timeout_ms}ms")
                false
            end
        end
      else
        false
      end
    else
      false
    end
  rescue
    e ->
      Logger.warning("[db_maintenance] SQLite VACUUM failed: #{Exception.message(e)}")
      false
  end

  defp database_path do
    # Resolve the same database path used by the repo
    case Repo.config()[:database] do
      path when is_binary(path) -> path
      _ -> ""
    end
  end

  defp run_vacuum_cmd(sqlite3, db_path, timeout_ms) do
    task = Task.async(fn -> System.cmd(sqlite3, [db_path, "VACUUM"], stderr_to_stdout: true) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> :timeout
    end
  end

  defp sqlite_adapter? do
    to_string(Repo.__adapter__()) == "Elixir.Ecto.Adapters.SQLite3"
  end

  # --- GenServer callbacks ---

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
      {:ok, %{events_pruned: count, vacuumed: vacuumed}} ->
        Logger.debug("[db_maintenance] sweep complete: pruned=#{count} vacuumed=#{vacuumed}")

      other ->
        Logger.warning("[db_maintenance] sweep returned #{inspect(other)}")
    end

    schedule(state)
    {:noreply, state}
  end

  defp schedule(%{interval_ms: interval_ms}) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :sweep, interval_ms)
  end

  defp schedule(_state), do: :ok

  # --- Config ---

  defp config_enabled? do
    maintenance_config() |> Keyword.get(:enabled, false)
  end

  defp env_enabled? do
    System.get_env("CK_DB_MAINTENANCE_SCHEDULER") in ~w(1 true TRUE yes YES)
  end

  defp config_interval_ms do
    maintenance_config() |> Keyword.get(:interval_ms, @default_interval_ms)
  end

  defp maintenance_config do
    Application.get_env(:controlkeel, :database_maintenance, [])
  end
end
