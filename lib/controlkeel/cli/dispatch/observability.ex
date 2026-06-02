defmodule ControlKeel.CLI.Dispatch.Observability do
  @moduledoc false
  
  require Logger
  alias ControlKeel.ACPRegistry
  alias ControlKeel.AgentExecution
  alias ControlKeel.AgentIntegration
  alias ControlKeel.AgentRouter
  alias ControlKeel.AttachedAgentSync
  alias ControlKeel.Analytics
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Benchmark
  alias ControlKeel.Budget
  alias ControlKeel.Budget.CostOptimizer
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.CodexConfig
  alias ControlKeel.Distribution
  alias ControlKeel.Deployment.Advisor
  alias ControlKeel.Deployment.HostingCost
  alias ControlKeel.Governance
  alias ControlKeel.Governance.AgentMonitor
  alias ControlKeel.Governance.CircuitBreaker
  alias ControlKeel.Governance.PreCommitHook
  alias ControlKeel.Governance.Socket, as: GovernanceSocket
  alias ControlKeel.CLI.Catalog
  alias ControlKeel.CLI.Parser
  alias ControlKeel.Help
  alias ControlKeel.Intent
  alias ControlKeel.Findings.PlainEnglish
  alias ControlKeel.Learning.OutcomeTracker
  alias ControlKeel.LocalProject
  alias ControlKeel.Memory
  alias ControlKeel.MCP.Tools.CkContext
  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry
  alias ControlKeel.Observability.Workshop, as: ObservabilityWorkshop
  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Platform
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProviderConfig
  alias ControlKeel.ProtocolAccess
  alias ControlKeel.ProjectBinding
  alias ControlKeel.ProjectRoot
  alias ControlKeel.ReviewBridge
  alias ControlKeel.Updater
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Proxy
  alias ControlKeel.RuntimePaths
  alias ControlKeel.SetupAdvisor
  alias ControlKeel.Skills
  alias ControlKeel.TaskAugmentation
  alias ControlKeel.WorkspaceContext
  alias ControlKeelWeb.Endpoint
  import ControlKeel.CLI, except: [run_command: 2]
  
  def run_command(%{command: :telemetry_enable, options: options}, _project_root) do
    alias ControlKeel.Cloud.TelemetryConfig

    with {:ok, raw_level} <- require_string_option(options[:level], "level"),
         {:ok, level} <- parse_telemetry_level(raw_level),
         {:ok, state} <- TelemetryConfig.enable(level) do
      {:ok,
       [
         "Cloud telemetry enabled",
         "Level: #{state.level}",
         "Workspace: #{state.workspace_id}",
         "Redaction policy version: #{state.redaction_policy_version}",
         "Config path: #{state.path}",
         "Note: this writes local state only. No remote sync is performed until the sync pipeline ships."
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}. Levels: #{telemetry_level_list_text()}"}

      {:error, :invalid_level} ->
        {:error, "Invalid level. Choose one of: #{telemetry_level_list_text()}"}

      {:error, :not_connected} ->
        {:error,
         "Workspace identity not found. Run `controlkeel cloud connect` first to generate a local identity."}

      {:error, {:write_failed, reason}} ->
        {:error, "Failed to persist telemetry config: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :telemetry_disable, options: _options}, _project_root) do
    case ControlKeel.Cloud.TelemetryConfig.disable() do
      {:ok, state} ->
        {:ok,
         [
           "Cloud telemetry disabled",
           "Level: #{state.level}",
           "Config path: #{state.path}"
         ]}

      {:error, {:write_failed, reason}} ->
        {:error, "Failed to persist telemetry config: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :baseline_compute, options: options}, _project_root) do
    workspace_id = options[:workspace_id]
    window_days = options[:window_days] || 7

    workspace_ids =
      if workspace_id do
        [workspace_id]
      else
        ControlKeel.Mission.list_workspaces()
        |> Enum.map(& &1.id)
      end

    if workspace_ids == [] do
      {:ok, ["No workspaces found."]}
    else
      results =
        Enum.map(workspace_ids, fn ws_id ->
          case ControlKeel.Cloud.BaselineAnalyzer.compute_and_store(ws_id,
                 window_days: window_days
               ) do
            {:ok, baseline} ->
              "workspace #{ws_id}: #{baseline.sample_sessions} sample sessions, #{baseline_tool_count(baseline)} tools, window #{window_days}d"

            {:error, reason} ->
              "workspace #{ws_id}: error — #{inspect(reason)}"
          end
        end)

      {:ok, ["Behavioral baselines computed:"] ++ results}
    end
  end

  def run_command(%{command: :obs_status, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      render_observability(session.id, format)
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_run, args: [session_id], options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      render_observability(session_id, format)
    end
  end

  def run_command(%{command: :obs_loop_status, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      loop =
        Observability.loop_status(
          workspace_id: session.workspace_id,
          limit: options[:limit] || 10
        )

      case format do
        "json" -> {:ok, [Jason.encode!(loop)]}
        _ -> {:ok, observability_loop_status_lines(loop)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_problems, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      problems = Observability.problems(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(problems)]}
        _ -> {:ok, observability_problem_lines(problems)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_costs, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      costs = Observability.costs(workspace_id: session.workspace_id, by: options[:by])

      case format do
        "json" -> {:ok, [Jason.encode!(costs)]}
        _ -> {:ok, observability_cost_lines(costs)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_imports, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      imports = Observability.imports(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(imports)]}
        _ -> {:ok, observability_import_list_lines(imports)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_trends, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      trends = Observability.trends(workspace_id: session.workspace_id, days: options[:days])

      case format do
        "json" -> {:ok, [Jason.encode!(trends)]}
        _ -> {:ok, observability_trend_lines(trends)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_regressions, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      regressions =
        Observability.regressions(
          workspace_id: session.workspace_id,
          days: options[:days],
          limit: options[:limit] || 12
        )

      case format do
        "json" -> {:ok, [Jason.encode!(regressions)]}
        _ -> {:ok, observability_regression_lines(regressions)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_recommend, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      recommendations = Observability.recommendations(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(recommendations)]}
        _ -> {:ok, observability_recommendation_lines(recommendations)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_evals, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      candidates = Observability.eval_candidates(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(candidates)]}
        _ -> {:ok, observability_eval_candidate_lines(candidates)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_evals_save, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      result = Observability.save_eval_candidates(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(result)]}
        _ -> {:ok, observability_eval_save_lines(result)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_evals_persisted, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      candidates = Observability.saved_eval_candidates(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(candidates)]}
        _ -> {:ok, observability_saved_eval_lines(candidates)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_draft, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      result = Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(result)]}
        _ -> {:ok, observability_benchmark_draft_result_lines(result)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_drafts, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      drafts = Observability.benchmark_drafts(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(drafts)]}
        _ -> {:ok, observability_benchmark_draft_lines(drafts)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_materialize, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      result = Observability.materialize_benchmark_drafts(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(result)]}
        _ -> {:ok, observability_benchmark_materialize_lines(result)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_scenarios, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      scenarios =
        Observability.observability_benchmark_scenarios(workspace_id: session.workspace_id)

      case format do
        "json" -> {:ok, [Jason.encode!(scenarios)]}
        _ -> {:ok, observability_benchmark_scenario_lines(scenarios)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_promotions, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      promotions =
        Observability.promotion_candidates(
          workspace_id: session.workspace_id,
          limit: options[:limit] || 50
        )

      case format do
        "json" -> {:ok, [Jason.encode!(promotions)]}
        _ -> {:ok, observability_promotion_lines(promotions)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_history, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      history =
        Observability.observability_benchmark_history(
          workspace_id: session.workspace_id,
          limit: options[:limit] || 12
        )

      case format do
        "json" -> {:ok, [Jason.encode!(history)]}
        _ -> {:ok, observability_benchmark_history_lines(history)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_benchmark_run, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      run_opts = observability_benchmark_run_options(options, session.workspace_id)

      case Observability.run_observability_benchmark(run_opts, project_root) do
        {:ok, result} ->
          case format do
            "json" -> {:ok, [Jason.encode!(result)]}
            _ -> {:ok, observability_benchmark_run_lines(result)}
          end

        {:error, :execute_required, preview} ->
          {:error,
           "Refusing to run without --execute. Preview command: #{preview.command || "materialize scenarios first"}"}

        {:error, :not_executable, preview} ->
          {:error,
           "Observability benchmark is not executable yet: #{Enum.join(preview.recommendations, " ")}"}

        {:error, reason, _preview} ->
          {:error, "Failed to run observability benchmark: #{inspect(reason)}"}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: command, args: [draft_id], options: options}, _project_root)
      when command in [:obs_benchmark_approve, :obs_benchmark_reject, :obs_benchmark_archive] do
    status = benchmark_status_for_command(command)

    with {:ok, format} <- effective_cli_format(options),
         {:ok, result} <-
           Observability.update_benchmark_draft_status(draft_id, status, reviewed_by: "cli") do
      case format do
        "json" -> {:ok, [Jason.encode!(result)]}
        _ -> {:ok, observability_benchmark_status_lines(result)}
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, :invalid_id} ->
        {:error, "Invalid benchmark draft id: #{draft_id}"}

      {:error, :not_found} ->
        {:error, "Benchmark draft not found: #{draft_id}"}

      {:error, :invalid_status} ->
        {:error, "Invalid benchmark draft status."}

      {:error, changeset} ->
        {:error, "Failed to update benchmark draft: #{inspect(changeset.errors)}"}
    end
  end

  def run_command(%{command: :obs_compare, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      comparison = Observability.comparison(workspace_id: session.workspace_id, by: options[:by])

      case format do
        "json" -> {:ok, [Jason.encode!(comparison)]}
        _ -> {:ok, observability_comparison_lines(comparison)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_timeline, args: args, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      session_id = List.first(args) || session.id
      limit = options[:limit] || 50

      render_observability_timeline(session_id, limit, format)
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_memory, args: args, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      session_id = List.first(args) || session.id
      limit = options[:limit] || 10

      render_observability_memory(session_id, limit, format)
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_memory_quality, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      quality =
        Observability.memory_quality(
          workspace_id: session.workspace_id,
          stale_days: options[:stale_days]
        )

      case format do
        "json" -> {:ok, [Jason.encode!(quality)]}
        _ -> {:ok, observability_memory_quality_lines(quality)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, reason} -> {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :obs_export, args: [session_id], options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, envelope} <- ObservabilityTelemetry.export_session(session_id) do
      case format do
        "json" -> {:ok, [Jason.encode!(envelope)]}
        _ -> {:ok, observability_export_lines(envelope)}
      end
    else
      {:error, {:invalid_output_format, message}} -> {:error, message}
      {:error, :not_found} -> {:error, "Session not found: #{session_id}"}
      {:error, :invalid_session_id} -> {:error, "Invalid session id: #{session_id}"}
    end
  end

  def run_command(%{command: :obs_import, args: [file_path], options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, result} <- observability_import(file_path, options, project_root) do
      case format do
        "json" -> {:ok, [Jason.encode!(result)]}
        _ -> {:ok, observability_import_lines(result)}
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, :dry_run_required} ->
        {:error, "Observability import requires --dry-run or --persist."}

      {:error, :enoent} ->
        {:error, "Observability import file was not found."}

      {:error, {:invalid_json, message}} ->
        {:error, "Observability import file must be valid JSON: #{message}"}

      {:error, {:missing_keys, keys}} ->
        {:error, "Observability envelope is missing required key(s): #{Enum.join(keys, ", ")}"}

      {:error, {:unsupported_schema_version, version}} ->
        {:error, "Unsupported observability schema version: #{inspect(version)}"}

      {:error, {:invalid_field, field}} ->
        {:error, "Observability envelope field `#{field}` has an invalid shape."}

      {:error, :invalid_envelope} ->
        {:error, "Observability import file must contain a JSON object envelope."}

      {:error, {:integrity_not_verified, status}} ->
        {:error,
         "Observability envelope integrity must be verified before persistence; got #{status || "unknown"}."}
    end
  end

  def run_command(%{command: :obs_workshop, args: [file_path], options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, preview} <- observability_workshop_preview(file_path, options) do
      case format do
        "json" -> {:ok, [Jason.encode!(preview)]}
        _ -> {:ok, observability_workshop_lines(preview)}
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, :dry_run_required} ->
        {:error, "Workshop observability preview requires --dry-run."}

      {:error, :enoent} ->
        {:error, "Workshop snapshot file was not found."}

      {:error, {:invalid_json, message}} ->
        {:error, "Workshop snapshot must be valid JSON: #{message}"}

      {:error, {:invalid_field, field}} ->
        {:error, "Workshop snapshot field `#{field}` has an invalid shape."}

      {:error, :invalid_workshop_snapshot} ->
        {:error, "Workshop snapshot must contain runs or a run with optional spans/live_events."}
    end
  end

end
