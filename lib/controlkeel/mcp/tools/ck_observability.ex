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
      persist = Keyword.get(opts, :persist, false)
      read_only = not persist
      mutation = if persist, do: "memory_record", else: "none"

      {:ok,
       %{
         report: report,
         read_only: read_only,
         mutation: mutation,
         data: dispatch_report(report, opts)
       }}
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
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, limit} <- optional_integer(arguments, "limit"),
         {:ok, days} <- optional_integer(arguments, "days"),
         {:ok, stale_days} <- optional_integer(arguments, "stale_days"),
         {:ok, by} <- optional_string(arguments, "by"),
         {:ok, project_root} <- optional_string(arguments, "project_root"),
         {:ok, persist} <- optional_boolean(arguments, "persist") do
      opts = []
      opts = if session_id, do: Keyword.put(opts, :session_id, session_id), else: opts
      opts = if workspace_id, do: Keyword.put(opts, :workspace_id, workspace_id), else: opts
      opts = if task_id, do: Keyword.put(opts, :task_id, task_id), else: opts
      opts = if limit, do: Keyword.put(opts, :limit, limit), else: opts
      opts = if days, do: Keyword.put(opts, :days, days), else: opts
      opts = if stale_days, do: Keyword.put(opts, :stale_days, stale_days), else: opts
      opts = if by, do: Keyword.put(opts, :by, by), else: opts
      opts = if project_root, do: Keyword.put(opts, :project_root, project_root), else: opts
      opts = if persist, do: Keyword.put(opts, :persist, persist), else: opts

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

  defp optional_boolean(arguments, key) do
    case Map.get(arguments, key) do
      nil ->
        {:ok, nil}

      value when is_boolean(value) ->
        {:ok, value}

      value when is_binary(value) ->
        lower = String.downcase(value)

        if lower in ["true", "1", "yes"],
          do: {:ok, true},
          else: if(lower in ["false", "0", "no"], do: {:ok, false}, else: {:ok, nil})

      _ ->
        {:ok, nil}
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

  defp dispatch_report("costs", opts) do
    base = Observability.costs(opts)

    case Keyword.get(opts, :project_root) do
      nil ->
        base

      project_root ->
        case ControlKeel.MCP.Tools.CkTokenAudit.call(%{
               "project_root" => project_root,
               "mode" => "full"
             }) do
          {:ok, token_audit} ->
            rule_recs =
              token_audit
              |> Map.get("recommendations", [])
              |> Enum.map(&"Token overhead: #{&1}")

            skill_recs =
              token_audit
              |> Map.get("skill_recommendations", [])
              |> Enum.take(3)
              |> Enum.map(&"Skill overhead: #{&1}")

            extra = rule_recs ++ skill_recs

            Map.update(base, :recommendations, extra, fn recs -> recs ++ extra end)

          _ ->
            base
        end
    end
  end

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
