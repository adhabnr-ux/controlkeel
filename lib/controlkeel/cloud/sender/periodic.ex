defmodule ControlKeel.Cloud.Sender.Periodic do
  @moduledoc """
  Background drainer that periodically calls `ControlKeel.Cloud.Sender.flush/0`.

  Idle by default — only does meaningful work when both
  `:cloud_telemetry_endpoint` is configured and the queue has pending events.
  Otherwise the timer just ticks and falls through.

  ## Configuration

      config :controlkeel,
        cloud_sender_periodic_enabled: true,    # default true
        cloud_sender_interval_ms: 60_000,       # default 60s between successful runs
        cloud_sender_backoff_initial_ms: 5_000, # default 5s after a failure
        cloud_sender_backoff_max_ms: 300_000    # default 5min cap

  ## Backoff

  After a failed flush (network error, 5xx, etc.) the next tick is delayed by
  the current backoff window, doubling each consecutive failure up to the cap.
  A successful flush resets the backoff.

  ## Status

  `status/0` returns the most recent outcome and the timestamp it ran. Used by
  `ControlKeel.Cloud.Doctor` to surface drainer health.
  """

  use GenServer

  require Logger

  alias ControlKeel.Cloud.Sender

  @default_interval_ms 60_000
  @default_backoff_initial_ms 5_000
  @default_backoff_max_ms 300_000

  @type status :: %{
          last_run_at: DateTime.t() | nil,
          last_outcome: term() | nil,
          consecutive_failures: non_neg_integer(),
          next_interval_ms: pos_integer()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return the latest drain outcome and counters."
  @spec status() :: status() | :not_running
  def status do
    case Process.whereis(__MODULE__) do
      nil -> :not_running
      pid -> GenServer.call(pid, :status)
    end
  end

  @doc "Force an immediate flush (skips the timer). Useful in tests."
  @spec flush_now() :: term()
  def flush_now do
    case Process.whereis(__MODULE__) do
      nil -> :not_running
      pid -> GenServer.call(pid, :flush_now, 30_000)
    end
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, configured(:cloud_sender_interval_ms, @default_interval_ms)),
      backoff_initial_ms:
        Keyword.get(opts, :backoff_initial_ms, configured(:cloud_sender_backoff_initial_ms, @default_backoff_initial_ms)),
      backoff_max_ms:
        Keyword.get(opts, :backoff_max_ms, configured(:cloud_sender_backoff_max_ms, @default_backoff_max_ms)),
      last_run_at: nil,
      last_outcome: nil,
      consecutive_failures: 0,
      next_interval_ms: nil,
      timer_ref: nil
    }

    state = %{state | next_interval_ms: state.interval_ms}
    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    state = run_flush(state)
    {:noreply, schedule_next(state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  @impl true
  def handle_call(:flush_now, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    state = run_flush(state)
    {:reply, state.last_outcome, schedule_next(state)}
  end

  defp run_flush(state) do
    outcome = safe_flush()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case classify(outcome) do
      :ok ->
        %{state | last_run_at: now, last_outcome: outcome, consecutive_failures: 0, next_interval_ms: state.interval_ms}

      :failure ->
        failures = state.consecutive_failures + 1
        next_ms = backoff_ms(state, failures)

        Logger.debug(
          "Cloud.Sender.Periodic: flush failed (#{inspect(outcome)}), backoff=#{next_ms}ms (consecutive=#{failures})"
        )

        %{state | last_run_at: now, last_outcome: outcome, consecutive_failures: failures, next_interval_ms: next_ms}

      :idle ->
        %{state | last_run_at: now, last_outcome: outcome, consecutive_failures: 0, next_interval_ms: state.interval_ms}
    end
  end

  defp safe_flush do
    Sender.flush()
  rescue
    error -> {:error, :crashed, Exception.message(error)}
  catch
    kind, value -> {:error, :crashed, "#{inspect(kind)} #{inspect(value)}"}
  end

  defp classify({:ok, :sent, _}), do: :ok
  defp classify({:ok, :no_pending, _}), do: :idle
  defp classify({:ok, :no_endpoint, _}), do: :idle
  defp classify({:error, _, _}), do: :failure
  defp classify(_), do: :failure

  defp backoff_ms(state, failures) do
    next = state.backoff_initial_ms * trunc(:math.pow(2, failures - 1))
    min(next, state.backoff_max_ms)
  end

  defp schedule_next(state) do
    ref = Process.send_after(self(), :tick, state.next_interval_ms)
    %{state | timer_ref: ref}
  end

  defp public_status(state) do
    %{
      last_run_at: state.last_run_at,
      last_outcome: state.last_outcome,
      consecutive_failures: state.consecutive_failures,
      next_interval_ms: state.next_interval_ms
    }
  end

  defp configured(key, default), do: Application.get_env(:controlkeel, key, default)
end
