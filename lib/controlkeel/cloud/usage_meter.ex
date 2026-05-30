defmodule ControlKeel.Cloud.UsageMeter do
  @moduledoc """
  Per-org daily usage aggregation backed by ETS.

  Records spend (in cents) keyed by `{org_id, date}`. The GenServer owns
  the ETS table and schedules an automatic midnight rollover.

  ## Design

  - Keys: `{{org_id, Date.t()}, :spend}}` → integer (cents accumulated)
  - Midnight rollover: schedules itself via `Process.send_after/3`
  - UsageEmitter: called after each record if configured
  - Survives process crash: ETS table is `public` with `write_concurrency`

  ## Future work (P4)

  - DB-backed persistence for durable billing records
  - Stripe Metering Events adapter via UsageEmitter behaviour
  """

  use GenServer

  require Logger

  @table :ck_cloud_usage_meter

  # ── Public API ──────────────────────────────────────────────────────

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Record `cents` of spend for `org_id` on today's date."
  @spec record(integer(), integer(), keyword()) :: :ok
  def record(org_id, cents, opts \\ []) when is_integer(org_id) and is_integer(cents) do
    date = Keyword.get(opts, :date, Date.utc_today())
    key = {org_id, date}

    # Fast path: direct ETS update (no GenServer round-trip for the counter)
    try do
      :ets.update_counter(@table, {:spend, key}, cents)
    rescue
      ArgumentError ->
        :ets.insert_new(@table, {{:spend, key}, cents})
    end

    # Emit to the configured emitter
    if Keyword.get(opts, :emit, true) do
      emit_usage(org_id, date)
    end

    :ok
  end

  @doc "Return today's spend for `org_id` in cents."
  @spec usage_today(integer()) :: integer()
  def usage_today(org_id) when is_integer(org_id) do
    usage_for_date(org_id, Date.utc_today())
  end

  @doc "Return spend for `org_id` on a specific date."
  @spec usage_for_date(integer(), Date.t()) :: integer()
  def usage_for_date(org_id, %Date{} = date) when is_integer(org_id) do
    case :ets.lookup(@table, {:spend, {org_id, date}}) do
      [{{:spend, {^org_id, ^date}}, cents}] -> cents
      [] -> 0
    end
  end

  @doc "Return total spend for `org_id` across a date range (inclusive)."
  @spec usage_range(integer(), Date.t(), Date.t()) :: %{Date.t() => integer()}
  @spec usage_range(integer(), Date.t(), Date.t(), :total) :: integer()
  def usage_range(org_id, %Date{} = from, %Date{} = to, mode \\ :map) do
    dates = Date.range(from, to)

    result =
      Enum.reduce(dates, %{}, fn date, acc ->
        Map.put(acc, date, usage_for_date(org_id, date))
      end)

    if mode == :total do
      Map.values(result) |> Enum.sum()
    else
      result
    end
  end

  @doc "Reset all usage data for `org_id`. Useful in tests."
  @spec reset(integer()) :: :ok
  def reset(org_id) when is_integer(org_id) do
    :ets.match_delete(@table, {{:spend, {org_id, :_}}, :_})
    :ok
  end

  @doc "Reset all usage data. Useful in test setup."
  @spec reset_all() :: :ok
  def reset_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, write_concurrency: true])

      _existing ->
        :ok
    end

    schedule_rollover()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:rollover, state) do
    # Future: archive yesterday's bucket to DB here.
    schedule_rollover()
    {:noreply, state}
  end

  # ── Private ────────────────────────────────────────────────────────

  defp schedule_rollover do
    now = DateTime.utc_now()
    tomorrow = Date.add(now, 1)
    midnight = DateTime.new!(tomorrow, ~T[00:00:00], "Etc/UTC")
    ms_until_midnight = max(DateTime.diff(midnight, now, :millisecond), 1)
    Process.send_after(self(), :rollover, ms_until_midnight)
  end

  defp emit_usage(org_id, date) do
    spend = usage_for_date(org_id, date)
    emitter = Application.get_env(:controlkeel, :usage_emitter, nil)

    if emitter do
      usage = %{org_id: org_id, date: date, spend_cents: spend}
      # Best-effort; never block the caller on emitter failures.
      try do
        emitter.emit_usage(org_id, usage)
      rescue
        e -> Logger.warning("UsageEmitter #{inspect(emitter)} failed: #{inspect(e)}")
      end
    end
  end
end
