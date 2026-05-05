defmodule ControlKeel.Integrations.Deepsec.Metrics do
  @moduledoc """
  Performance metrics tracking for deepsec scans.

  This module provides metrics collection and reporting for
  deepsec scan performance, including timing, resource usage,
  and finding statistics.
  """

  use GenServer

  require Logger

  @table_name :deepsec_metrics

  ## Client API

  @doc """
  Starts the metrics server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records the start of a scan.
  """
  def scan_start(session_id, workspace_path) do
    GenServer.cast(__MODULE__, {:scan_start, session_id, workspace_path})
  end

  @doc """
  Records the end of a scan.
  """
  def scan_end(session_id, findings_count) do
    GenServer.cast(__MODULE__, {:scan_end, session_id, findings_count})
  end

  @doc """
  Records a step in the scan process.
  """
  def record_step(session_id, step_name, duration_ms) do
    GenServer.cast(__MODULE__, {:record_step, session_id, step_name, duration_ms})
  end

  @doc """
  Gets metrics for a session.
  """
  def get_metrics(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{_key, metrics}] -> {:ok, metrics}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets all metrics.
  """
  def get_all_metrics do
    :ets.tab2list(@table_name)
  end

  @doc """
  Gets aggregated metrics across all sessions.
  """
  def get_aggregated_metrics do
    all_metrics = get_all_metrics()

    total_scans = length(all_metrics)

    if total_scans == 0 do
      %{total_scans: 0}
    else
      total_duration =
        Enum.reduce(all_metrics, 0, fn {_session, metrics}, acc ->
          acc + Map.get(metrics, :total_duration_ms, 0)
        end)

      total_findings =
        Enum.reduce(all_metrics, 0, fn {_session, metrics}, acc ->
          acc + Map.get(metrics, :findings_count, 0)
        end)

      avg_duration = total_duration / total_scans
      avg_findings = total_findings / total_scans

      %{
        total_scans: total_scans,
        total_duration_ms: total_duration,
        total_findings: total_findings,
        avg_duration_ms: avg_duration,
        avg_findings: avg_findings
      }
    end
  end

  @doc """
  Clears metrics for a session.
  """
  def clear_metrics(session_id) do
    :ets.delete(@table_name, session_id)
    :ok
  end

  @doc """
  Clears all metrics.
  """
  def clear_all_metrics do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Records a custom metric.
  """
  def record_metric(session_id, key, value) do
    GenServer.cast(__MODULE__, {:record_metric, session_id, key, value})
  end

  @doc """
  Gets metrics in a human-readable format.
  """
  def format_metrics(metrics) when is_map(metrics) do
    """
    Deepsec Scan Metrics
    =====================
    Session: #{Map.get(metrics, :session_id, "unknown")}
    Workspace: #{Map.get(metrics, :workspace_path, "unknown")}
    Status: #{Map.get(metrics, :status, "unknown")}
    Start Time: #{format_timestamp(Map.get(metrics, :start_time))}
    End Time: #{format_timestamp(Map.get(metrics, :end_time))}
    Total Duration: #{Map.get(metrics, :total_duration_ms, 0)}ms
    Findings Count: #{Map.get(metrics, :findings_count, 0)}

    Steps:
    #{format_steps(Map.get(metrics, :steps, []))}
    """
  end

  @doc """
  Tracks a function execution and records timing metrics.
  """
  def track_execution(session_id, step_name, fun) when is_function(fun) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      record_step(session_id, step_name, duration_ms)
      {:ok, result, duration_ms}
    rescue
      e ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        record_step(session_id, "#{step_name}_error", duration_ms)
        {:error, e, duration_ms}
    end
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public])
    Logger.info("Deepsec metrics server started")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:scan_start, session_id, workspace_path}, state) do
    metrics = %{
      session_id: session_id,
      workspace_path: workspace_path,
      status: "running",
      start_time: System.system_time(:millisecond),
      end_time: nil,
      total_duration_ms: 0,
      findings_count: 0,
      steps: []
    }

    :ets.insert(state.table, {session_id, metrics})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:scan_end, session_id, findings_count}, state) do
    case :ets.lookup(state.table, session_id) do
      [{_key, metrics}] ->
        end_time = System.system_time(:millisecond)
        total_duration_ms = end_time - Map.get(metrics, :start_time, 0)

        updated =
          metrics
          |> Map.put(:status, "completed")
          |> Map.put(:end_time, end_time)
          |> Map.put(:total_duration_ms, total_duration_ms)
          |> Map.put(:findings_count, findings_count)

        :ets.insert(state.table, {session_id, updated})
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:record_step, session_id, step_name, duration_ms}, state) do
    case :ets.lookup(state.table, session_id) do
      [{_key, metrics}] ->
        step = %{
          name: step_name,
          duration_ms: duration_ms,
          timestamp: System.system_time(:millisecond)
        }

        steps = Map.get(metrics, :steps, []) ++ [step]
        updated = Map.put(metrics, :steps, steps)

        :ets.insert(state.table, {session_id, updated})
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:record_metric, session_id, key, value}, state) do
    case :ets.lookup(state.table, session_id) do
      [{_key, metrics}] ->
        updated = Map.put(metrics, key, value)
        :ets.insert(state.table, {session_id, updated})
        {:noreply, state}

      [] ->
        {:noreply, state}
    end
  end

  ## Private Functions

  defp format_timestamp(nil), do: "N/A"

  defp format_timestamp(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp, :millisecond)
    |> DateTime.to_iso8601()
  end

  defp format_timestamp(_), do: "N/A"

  defp format_steps([]), do: "  No steps recorded"

  defp format_steps(steps) do
    steps
    |> Enum.map(fn step ->
      "  - #{step.name}: #{step.duration_ms}ms"
    end)
    |> Enum.join("\n")
  end
end
