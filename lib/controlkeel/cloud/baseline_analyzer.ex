defmodule ControlKeel.Cloud.BaselineAnalyzer do
  @moduledoc """
  Behavioral baselining for workspace sessions.

  Computes a rolling per-tool baseline (calls/session, tokens/call) from the
  last N days of invocations for each workspace. Deviation detection compares
  a live session's observed metrics against the stored baseline and emits
  findings when values exceed the configured threshold multiplier.

  ## Workflow

    1. `compute_and_store/1` — recompute the baseline for a workspace and
       persist it in `workspace_baselines`. Call periodically (e.g., nightly).
    2. `detect_deviations/2` — compare a session's recent invocations against
       the stored baseline. Returns a list of deviation maps.
    3. `check_session/1` — convenience wrapper that runs detect_deviations and
       calls `Mission.create_finding/1` for each new deviation.

  ## Baseline data shape (stored as JSON)

      %{
        "tool_name" => %{
          "mean_calls_per_session" => float,
          "mean_input_tokens"      => float,
          "mean_output_tokens"     => float,
          "sample_count"           => integer
        }
      }
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.WorkspaceBaseline
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Invocation, Session}
  alias ControlKeel.Repo

  @default_window_days 7
  @deviation_threshold 3.0
  @min_samples 3

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Compute the rolling baseline for `workspace_id` and persist it.

  Options:
    - `:window_days` — look-back window (default 7)
  """
  @spec compute_and_store(integer(), keyword()) ::
          {:ok, WorkspaceBaseline.t()} | {:error, term()}
  def compute_and_store(workspace_id, opts \\ []) when is_integer(workspace_id) do
    window_days = Keyword.get(opts, :window_days, @default_window_days)
    {baseline_map, sample_sessions} = build_baseline(workspace_id, window_days)

    attrs = %{
      workspace_id: workspace_id,
      window_days: window_days,
      baseline_data: Jason.encode!(baseline_map),
      sample_sessions: sample_sessions,
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    existing = Repo.get_by(WorkspaceBaseline, workspace_id: workspace_id)

    changeset =
      case existing do
        nil -> WorkspaceBaseline.changeset(%WorkspaceBaseline{}, attrs)
        record -> WorkspaceBaseline.changeset(record, attrs)
      end

    Repo.insert_or_update(changeset)
  end

  @doc """
  Compare `session`'s invocations over the last `window_hours` hours against
  the stored baseline for its workspace. Returns a (possibly empty) list of
  deviation maps:

      %{
        tool: tool_name,
        metric: :calls | :input_tokens | :output_tokens,
        observed: number,
        baseline_mean: number,
        ratio: float
      }

  Returns `[]` when no baseline exists or has fewer than `@min_samples` sessions.
  """
  @spec detect_deviations(Session.t(), keyword()) :: [map()]
  def detect_deviations(%Session{workspace_id: workspace_id} = session, opts \\ [])
      when is_integer(workspace_id) do
    window_hours = Keyword.get(opts, :window_hours, 1)
    threshold = Keyword.get(opts, :threshold, @deviation_threshold)

    case Repo.get_by(WorkspaceBaseline, workspace_id: workspace_id) do
      nil ->
        []

      %WorkspaceBaseline{sample_sessions: n} when n < @min_samples ->
        []

      baseline_record ->
        baseline = WorkspaceBaseline.decode(baseline_record)
        session_metrics = session_tool_metrics(session.id, window_hours)
        deviations_for(session_metrics, baseline, threshold)
    end
  end

  @doc """
  Detect deviations for `session` and persist a finding for each one.
  Returns `{:ok, [findings]}` (may be empty).
  """
  @spec check_session(Session.t(), keyword()) :: {:ok, [map()]}
  def check_session(%Session{} = session, opts \\ []) do
    deviations = detect_deviations(session, opts)

    findings =
      Enum.flat_map(deviations, fn dev ->
        attrs = deviation_finding_attrs(session, dev)

        case Mission.create_finding(attrs) do
          {:ok, finding} -> [finding]
          _ -> []
        end
      end)

    {:ok, findings}
  end

  @doc """
  Returns the stored baseline for `workspace_id`, or `nil`.
  """
  @spec get_baseline(integer()) :: WorkspaceBaseline.t() | nil
  def get_baseline(workspace_id), do: Repo.get_by(WorkspaceBaseline, workspace_id: workspace_id)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_baseline(workspace_id, window_days) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-window_days * 86_400, :second)
      |> DateTime.truncate(:second)

    rows =
      from(i in Invocation,
        join: s in Session,
        on: s.id == i.session_id,
        where: s.workspace_id == ^workspace_id,
        where: i.inserted_at >= ^since,
        where: not is_nil(i.tool),
        group_by: [i.session_id, i.tool],
        select: %{
          session_id: i.session_id,
          tool: i.tool,
          call_count: count(i.id),
          input_tokens: sum(i.input_tokens),
          output_tokens: sum(i.output_tokens)
        }
      )
      |> Repo.all()

    sample_sessions = rows |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()

    baseline =
      rows
      |> Enum.group_by(& &1.tool)
      |> Enum.map(fn {tool, tool_rows} ->
        n = length(tool_rows)
        mean_calls = avg(Enum.map(tool_rows, & &1.call_count))
        mean_input = avg(Enum.map(tool_rows, & &1.input_tokens))
        mean_output = avg(Enum.map(tool_rows, & &1.output_tokens))

        {tool,
         %{
           "mean_calls_per_session" => mean_calls,
           "mean_input_tokens" => mean_input,
           "mean_output_tokens" => mean_output,
           "sample_count" => n
         }}
      end)
      |> Map.new()

    {baseline, sample_sessions}
  end

  defp session_tool_metrics(session_id, window_hours) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-window_hours * 3_600, :second)
      |> DateTime.truncate(:second)

    from(i in Invocation,
      where: i.session_id == ^session_id,
      where: i.inserted_at >= ^since,
      where: not is_nil(i.tool),
      group_by: i.tool,
      select: %{
        tool: i.tool,
        call_count: count(i.id),
        input_tokens: sum(i.input_tokens),
        output_tokens: sum(i.output_tokens)
      }
    )
    |> Repo.all()
  end

  defp deviations_for(session_metrics, baseline, threshold) do
    Enum.flat_map(session_metrics, fn row ->
      case Map.get(baseline, row.tool) do
        nil ->
          []

        bline ->
          [
            check_metric(
              row.tool,
              :calls,
              row.call_count,
              bline["mean_calls_per_session"],
              threshold
            ),
            check_metric(
              row.tool,
              :input_tokens,
              row.input_tokens,
              bline["mean_input_tokens"],
              threshold
            ),
            check_metric(
              row.tool,
              :output_tokens,
              row.output_tokens,
              bline["mean_output_tokens"],
              threshold
            )
          ]
          |> Enum.reject(&is_nil/1)
      end
    end)
  end

  defp check_metric(_tool, _metric, _observed, baseline_mean, _threshold)
       when is_nil(baseline_mean) or baseline_mean == 0,
       do: nil

  defp check_metric(tool, metric, observed, baseline_mean, threshold)
       when is_integer(observed) or is_float(observed) do
    ratio = (observed || 0) / baseline_mean

    if ratio >= threshold do
      %{
        tool: tool,
        metric: metric,
        observed: observed,
        baseline_mean: baseline_mean,
        ratio: Float.round(ratio, 2)
      }
    end
  end

  defp check_metric(_tool, _metric, _observed, _baseline_mean, _threshold), do: nil

  defp deviation_finding_attrs(session, dev) do
    metric_label =
      case dev.metric do
        :calls -> "calls/session"
        :input_tokens -> "input tokens"
        :output_tokens -> "output tokens"
      end

    %{
      title: "Behavioral anomaly: #{dev.tool} #{metric_label} #{dev.ratio}× baseline",
      severity: if(dev.ratio >= 10.0, do: "high", else: "medium"),
      category: "behavioral",
      rule_id: "behavioral.anomaly.#{dev.metric}",
      plain_message:
        "Tool #{dev.tool} #{metric_label} is #{dev.ratio}× the workspace baseline " <>
          "(observed: #{dev.observed}, baseline mean: #{dev.baseline_mean}).",
      status: "open",
      auto_resolved: false,
      metadata: %{
        "tool" => dev.tool,
        "metric" => Atom.to_string(dev.metric),
        "observed" => dev.observed,
        "baseline_mean" => dev.baseline_mean,
        "ratio" => dev.ratio,
        "scanner" => "baseline_analyzer"
      },
      session_id: session.id
    }
  end

  defp avg([]), do: 0.0
  defp avg(values), do: Enum.sum(values) / length(values)
end
