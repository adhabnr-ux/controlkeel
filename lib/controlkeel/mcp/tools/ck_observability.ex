defmodule ControlKeel.MCP.Tools.CkObservability do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @reports [
    "overview",
    "loop_status",
    "session_run",
    "timeline",
    "memory",
    "memory_quality",
    "recommendations",
    "costs",
    "compare",
    "imports",
    "trends",
    "problems",
    "evals",
    "saved_evals",
    "benchmark_drafts",
    "benchmark_scenarios",
    "benchmark_history",
    "perf_snapshot",
    "promotions",
    "regressions"
  ]

  def call(arguments) when is_map(arguments) do
    with {:ok, report} <- report(arguments),
         {:ok, opts} <- report_opts(arguments) do
      {:ok,
       %{report: report, read_only: true, mutation: "none", data: dispatch_report(report, opts)}}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  def reports, do: @reports

  defp report(arguments) do
    value = Map.get(arguments, "report") || Map.get(arguments, "surface") || "overview"

    if value in @reports do
      {:ok, value}
    else
      {:error, {:invalid_arguments, "`report` must be one of: #{Enum.join(@reports, ", ")}"}}
    end
  end

  defp report_opts(arguments) do
    with {:ok, session_id} <- optional_integer(arguments, "session_id"),
         {:ok, workspace_id} <- optional_integer(arguments, "workspace_id"),
         {:ok, limit} <- optional_integer(arguments, "limit"),
         {:ok, days} <- optional_integer(arguments, "days"),
         {:ok, stale_days} <- optional_integer(arguments, "stale_days"),
         {:ok, by} <- optional_string(arguments, "by") do
      opts = []
      opts = if session_id, do: Keyword.put(opts, :session_id, session_id), else: opts
      opts = if workspace_id, do: Keyword.put(opts, :workspace_id, workspace_id), else: opts
      opts = if limit, do: Keyword.put(opts, :limit, limit), else: opts
      opts = if days, do: Keyword.put(opts, :days, days), else: opts
      opts = if stale_days, do: Keyword.put(opts, :stale_days, stale_days), else: opts
      opts = if by, do: Keyword.put(opts, :by, by), else: opts

      opts =
        if workspace_id || session_id do
          opts
        else
          case Arguments.resolve_session_id(arguments) do
            {:ok, resolved_session_id} ->
              case Mission.get_session(resolved_session_id) do
                %{workspace_id: resolved_workspace_id} ->
                  opts
                  |> Keyword.put(:session_id, resolved_session_id)
                  |> Keyword.put(:workspace_id, resolved_workspace_id)

                _ ->
                  Keyword.put(opts, :session_id, resolved_session_id)
              end

            _ ->
              opts
          end
        end

      {:ok, opts}
    end
  end

  defp optional_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> Arguments.normalize_integer(value, key)
    end
  end

  defp optional_string(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      value -> {:ok, to_string(value)}
    end
  end

  defp dispatch_report("overview", opts), do: Observability.workspace_overview(opts)
  defp dispatch_report("loop_status", opts), do: Observability.loop_status(opts)

  defp dispatch_report("session_run", opts),
    do: session_report(opts, &Observability.session_run/2)

  defp dispatch_report("timeline", opts), do: session_report(opts, &Observability.timeline/2)
  defp dispatch_report("memory", opts), do: session_report(opts, &Observability.memory_context/2)
  defp dispatch_report("memory_quality", opts), do: Observability.memory_quality(opts)
  defp dispatch_report("recommendations", opts), do: Observability.recommendations(opts)
  defp dispatch_report("costs", opts), do: Observability.costs(opts)
  defp dispatch_report("compare", opts), do: Observability.comparison(opts)
  defp dispatch_report("imports", opts), do: Observability.imports(opts)
  defp dispatch_report("trends", opts), do: Observability.trends(opts)
  defp dispatch_report("problems", opts), do: Observability.problems(opts)
  defp dispatch_report("evals", opts), do: Observability.eval_candidates(opts)
  defp dispatch_report("saved_evals", opts), do: Observability.saved_eval_candidates(opts)
  defp dispatch_report("benchmark_drafts", opts), do: Observability.benchmark_drafts(opts)

  defp dispatch_report("benchmark_scenarios", opts),
    do: Observability.observability_benchmark_scenarios(opts)

  defp dispatch_report("benchmark_history", opts),
    do: Observability.observability_benchmark_history(opts)

  defp dispatch_report("perf_snapshot", opts), do: Observability.perf_snapshot(opts)

  defp dispatch_report("promotions", opts), do: Observability.promotion_candidates(opts)
  defp dispatch_report("regressions", opts), do: Observability.regressions(opts)

  defp session_report(opts, fun) do
    case Keyword.get(opts, :session_id) do
      nil -> %{error: "session_id_required", message: "This report requires a session_id."}
      session_id -> unwrap_session_report(fun.(session_id, opts))
    end
  end

  defp unwrap_session_report({:ok, report}), do: report
  defp unwrap_session_report({:error, reason}), do: %{error: to_string(reason)}
  defp unwrap_session_report(report), do: report
end
