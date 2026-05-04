defmodule ControlKeel.MCP.Protocol do
  @moduledoc false
  require Logger

  alias ControlKeel.Intent.Domains
  alias ControlKeel.SecurityWorkflow
  alias ControlKeel.Skills.Registry
  alias ControlKeel.TrustBoundary

  alias ControlKeel.MCP.Tools.{
    CkBudget,
    CkContext,
    CkContextPack,
    CkExecuteCode,
    CkDelegate,
    CkExperienceIndex,
    CkExperienceRead,
    CkExperienceSearch,
    CkFsFind,
    CkFsGrep,
    CkFsLs,
    CkFsRead,
    CkFailureClusters,
    CkFinding,
    CkGoal,
    CkLoadResources,
    CkMemoryArchive,
    CkMemoryRecord,
    CkMemorySearch,
    CkMcpDiscover,
    CkObservability,
    CkSkillEvolution,
    CkReviewFeedback,
    CkRegressionResult,
    CkReviewStatus,
    CkReviewSubmit,
    CkRoute,
    CkTracePacket,
    CkSkillList,
    CkSkillLoad,
    CkSkillValidate,
    CkValidate,
    CkCostOptimizer,
    CkDeploymentAdvisor,
    CkOutcomeTracker,
    CkTokenAudit,
    CkToolHealth,
    CkWorktreeList,
    CkWorktreeSwitch,
    CkCheckpointCreate,
    CkCheckpointRestore,
    CkCheckpointList,
    CkGitDiff,
    CkGitCommit,
    CkGitStatus,
    CkMonitorSubscribe
  }

  @server_info %{
    "name" => "controlkeel",
    "version" => to_string(Application.spec(:controlkeel, :vsn) || "0.2.0")
  }

  def handle_json(payload, opts \\ []) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, []} ->
        error_response(nil, -32600, "Invalid Request")

      {:ok, requests} when is_list(requests) ->
        json_rpc_batch_responses(requests, opts)

      {:ok, request} when is_map(request) ->
        handle_request(request, opts)

      {:ok, _} ->
        error_response(nil, -32600, "Invalid Request")

      {:error, error} ->
        error_response(nil, -32700, "Parse error: #{Exception.message(error)}")
    end
  end

  # JSON-RPC 2.0 batch + MCP: clients MAY batch; servers MUST accept batches.
  # A lone Array was previously routed to handle_request/2 and fell through to
  # "Invalid Request" with id null, which breaks Cursor's handshake (20s timeout).
  defp json_rpc_batch_responses(requests, opts) when is_list(requests) do
    responses =
      Enum.flat_map(requests, fn
        %{"jsonrpc" => "2.0"} = req ->
          if json_rpc_notification?(req) do
            _ = handle_request(req, opts)
            []
          else
            [handle_request(req, opts)]
          end

        _not_object ->
          [error_response(nil, -32600, "Invalid Request")]
      end)

    case responses do
      [] -> :no_response
      list when is_list(list) -> list
    end
  end

  defp json_rpc_notification?(req) when is_map(req), do: not Map.has_key?(req, "id")

  def handle_request(request, opts \\ [])

  def handle_request(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id} = req, _opts) do
    requested = get_in(req, ["params", "protocolVersion"])
    negotiated = negotiate_mcp_protocol_version(requested)

    ok_response(id, %{
      "protocolVersion" => negotiated,
      "capabilities" => %{
        "tools" => %{"listChanged" => false},
        "resources" => %{"subscribe" => false, "listChanged" => false}
      },
      "serverInfo" => @server_info
    })
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _opts),
    do: :no_response

  def handle_request(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, opts) do
    ok_response(id, %{"tools" => tool_schemas(opts)})
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => "resources/list", "id" => id}, opts) do
    ok_response(id, %{"resources" => resource_schemas(opts)})
  end

  def handle_request(
        %{"jsonrpc" => "2.0", "method" => "resources/read", "id" => id, "params" => params},
        _opts
      ) do
    case mcp_stdio_boot_gate(id) do
      :ok ->
        case params do
          %{"uri" => uri} ->
            resource_response(id, load_resource(uri, params))

          _ ->
            error_response(id, -32602, "resources/read requires a resource uri")
        end

      {:error, response} ->
        response
    end
  end

  def handle_request(
        %{
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "id" => id,
          "params" => params
        },
        opts
      ) do
    case mcp_stdio_boot_gate(id) do
      :ok ->
        case params do
          %{"name" => name, "arguments" => arguments} ->
            with :ok <- authorize_tool(name, arguments, opts) do
              tool_response(id, dispatch_tool(name, arguments))
            else
              {:error, {:forbidden, reason}} ->
                error_response(id, -32001, reason)

              {:error, reason} ->
                error_response(id, -32602, inspect(reason))
            end

          _other ->
            error_response(id, -32602, "tools/call requires a tool name and arguments")
        end

      {:error, response} ->
        response
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => _method, "id" => id}, _opts) do
    error_response(id, -32601, "Method not found")
  end

  def handle_request(_request, _opts) do
    error_response(nil, -32600, "Invalid Request")
  end

  @tool_groups %{
    "core" => [
      "ck_validate",
      "ck_context",
      "ck_context_pack",
      "ck_execute_code",
      "ck_budget",
      "ck_route",
      "ck_mcp_discover",
      "ck_token_audit"
    ],
    "governance" => [
      "ck_review_submit",
      "ck_review_status",
      "ck_review_feedback",
      "ck_regression_result",
      "ck_finding",
      "ck_goal",
      "ck_memory_record",
      "ck_memory_search",
      "ck_memory_archive",
      "ck_delegate",
      "ck_cost_optimizer",
      "ck_deployment_advisor",
      "ck_outcome_tracker"
    ],
    "observability" => [
      "ck_observability",
      "ck_experience_index",
      "ck_experience_read",
      "ck_experience_search",
      "ck_trace_packet",
      "ck_failure_clusters",
      "ck_monitor_subscribe",
      "ck_tool_health",
      "ck_skill_evolution"
    ],
    "skills" => [
      "ck_skill_list",
      "ck_skill_load",
      "ck_skill_validate",
      "ck_load_resources"
    ],
    "filesystem" => [
      "ck_fs_ls",
      "ck_fs_read",
      "ck_fs_find",
      "ck_fs_grep"
    ],
    "git" => [
      "ck_git_status",
      "ck_git_diff",
      "ck_git_commit"
    ],
    "checkpoints" => [
      "ck_checkpoint_create",
      "ck_checkpoint_restore",
      "ck_checkpoint_list"
    ],
    "worktrees" => [
      "ck_worktree_list",
      "ck_worktree_switch"
    ]
  }

  def tool_schemas(opts \\ []) do
    base = [
      ck_validate_tool(),
      ck_execute_code_tool(),
      ck_context_tool(),
      ck_context_pack_tool(),
      ck_observability_tool(),
      ck_experience_index_tool(),
      ck_experience_read_tool(),
      ck_experience_search_tool(),
      ck_trace_packet_tool(),
      ck_failure_clusters_tool(),
      ck_tool_health_tool(),
      ck_skill_evolution_tool(),
      ck_fs_ls_tool(),
      ck_fs_read_tool(),
      ck_fs_find_tool(),
      ck_fs_grep_tool(),
      ck_worktree_list_tool(),
      ck_worktree_switch_tool(),
      ck_checkpoint_create_tool(),
      ck_checkpoint_restore_tool(),
      ck_checkpoint_list_tool(),
      ck_git_diff_tool(),
      ck_git_commit_tool(),
      ck_git_status_tool(),
      ck_monitor_subscribe_tool(),
      ck_finding_tool(),
      ck_review_submit_tool(),
      ck_review_status_tool(),
      ck_review_feedback_tool(),
      ck_regression_result_tool(),
      ck_memory_search_tool(),
      ck_memory_record_tool(),
      ck_goal_tool(),
      ck_memory_archive_tool(),
      ck_budget_tool(),
      ck_route_tool(),
      ck_delegate_tool(),
      ck_cost_optimizer_tool(),
      ck_deployment_advisor_tool(),
      ck_outcome_tracker_tool(),
      ck_load_resources_tool(),
      ck_mcp_discover_tool(),
      ck_token_audit_tool()
    ]

    # Always expose ck_skill_list / ck_skill_load / ck_skill_validate. Do not call Registry here: a full
    # catalog walk (every agent skill dir under $HOME) can take 10–30s and blocks this
    # process while Cursor expects tools/list under a ~20s connect budget.
    tools = base ++ [ck_skill_list_tool(), ck_skill_load_tool(), ck_skill_validate_tool()]

    # Apply tool_names filtering (takes precedence over tool_groups and adaptive mode)
    # This is used by hosted mode for security - explicit tool whitelisting
    filtered_tools =
      case Keyword.get(opts, :tool_names) do
        names when is_list(names) ->
          Enum.filter(tools, &(&1["name"] in names))

        _ ->
          # Apply tool group filtering — opts take precedence over env var.
          # :all in opts means "force all tools, bypass env var" (used by audit/measurement callers).
          # When opts does not specify tool_groups, fall back to env var / app config.
          # NEW: Check for per-project adaptive preferences and enable auto-expansion
          project_root = Keyword.get(opts, :project_root)
          adaptive_mode = Keyword.get(opts, :adaptive, true)

          effective_groups =
            case Keyword.fetch(opts, :tool_groups) do
              {:ok, :all} ->
                :all

              {:ok, groups} ->
                groups

              :error ->
                if adaptive_mode && project_root do
                  adaptive_tool_groups(project_root)
                else
                  env_tool_groups() || :all
                end
            end

          case effective_groups do
            :all ->
              tools

            groups when is_list(groups) ->
              allowed_tool_names =
                groups
                |> Enum.flat_map(fn group -> Map.get(@tool_groups, group, []) end)
                |> MapSet.new()

              filtered = Enum.filter(tools, &(&1["name"] in allowed_tool_names))

              if adaptive_mode && project_root do
                log_tool_group_decision(project_root, groups, length(tools), length(filtered))
              end

              filtered

            _ ->
              tools
          end
      end

    filtered_tools
  end

  def dispatch_tool(tool_name, arguments) do
    # Track usage for adaptive learning
    project_root = stdio_project_root()
    track_tool_usage(project_root, tool_name)

    # Call the actual tool implementation
    do_dispatch_tool(tool_name, arguments)
  end

  defp do_dispatch_tool("ck_validate", arguments), do: CkValidate.call(arguments)
  defp do_dispatch_tool("ck_execute_code", arguments), do: CkExecuteCode.call(arguments)
  defp do_dispatch_tool("ck_context", arguments), do: CkContext.call(arguments)
  defp do_dispatch_tool("ck_context_pack", arguments), do: CkContextPack.call(arguments)
  defp do_dispatch_tool("ck_observability", arguments), do: CkObservability.call(arguments)
  defp do_dispatch_tool("ck_experience_index", arguments), do: CkExperienceIndex.call(arguments)
  defp do_dispatch_tool("ck_experience_read", arguments), do: CkExperienceRead.call(arguments)
  defp do_dispatch_tool("ck_experience_search", arguments), do: CkExperienceSearch.call(arguments)
  defp do_dispatch_tool("ck_trace_packet", arguments), do: CkTracePacket.call(arguments)
  defp do_dispatch_tool("ck_failure_clusters", arguments), do: CkFailureClusters.call(arguments)
  defp do_dispatch_tool("ck_tool_health", arguments), do: CkToolHealth.call(arguments)
  defp do_dispatch_tool("ck_skill_evolution", arguments), do: CkSkillEvolution.call(arguments)
  defp do_dispatch_tool("ck_fs_ls", arguments), do: CkFsLs.call(arguments)
  defp do_dispatch_tool("ck_fs_read", arguments), do: CkFsRead.call(arguments)
  defp do_dispatch_tool("ck_fs_find", arguments), do: CkFsFind.call(arguments)
  defp do_dispatch_tool("ck_fs_grep", arguments), do: CkFsGrep.call(arguments)
  defp do_dispatch_tool("ck_worktree_list", arguments), do: CkWorktreeList.call(arguments)
  defp do_dispatch_tool("ck_worktree_switch", arguments), do: CkWorktreeSwitch.call(arguments)
  defp do_dispatch_tool("ck_checkpoint_create", arguments), do: CkCheckpointCreate.call(arguments)

  defp do_dispatch_tool("ck_checkpoint_restore", arguments),
    do: CkCheckpointRestore.call(arguments)

  defp do_dispatch_tool("ck_checkpoint_list", arguments), do: CkCheckpointList.call(arguments)
  defp do_dispatch_tool("ck_git_diff", arguments), do: CkGitDiff.call(arguments)
  defp do_dispatch_tool("ck_git_commit", arguments), do: CkGitCommit.call(arguments)
  defp do_dispatch_tool("ck_git_status", arguments), do: CkGitStatus.call(arguments)
  defp do_dispatch_tool("ck_monitor_subscribe", arguments), do: CkMonitorSubscribe.call(arguments)
  defp do_dispatch_tool("ck_finding", arguments), do: CkFinding.call(arguments)
  defp do_dispatch_tool("ck_review_submit", arguments), do: CkReviewSubmit.call(arguments)
  defp do_dispatch_tool("ck_review_status", arguments), do: CkReviewStatus.call(arguments)
  defp do_dispatch_tool("ck_review_feedback", arguments), do: CkReviewFeedback.call(arguments)
  defp do_dispatch_tool("ck_regression_result", arguments), do: CkRegressionResult.call(arguments)
  defp do_dispatch_tool("ck_memory_search", arguments), do: CkMemorySearch.call(arguments)
  defp do_dispatch_tool("ck_memory_record", arguments), do: CkMemoryRecord.call(arguments)
  defp do_dispatch_tool("ck_goal", arguments), do: CkGoal.call(arguments)
  defp do_dispatch_tool("ck_memory_archive", arguments), do: CkMemoryArchive.call(arguments)
  defp do_dispatch_tool("ck_budget", arguments), do: CkBudget.call(arguments)
  defp do_dispatch_tool("ck_route", arguments), do: CkRoute.call(arguments)
  defp do_dispatch_tool("ck_delegate", arguments), do: CkDelegate.call(arguments)
  defp do_dispatch_tool("ck_skill_list", arguments), do: CkSkillList.call(arguments)
  defp do_dispatch_tool("ck_skill_load", arguments), do: CkSkillLoad.call(arguments)
  defp do_dispatch_tool("ck_skill_validate", arguments), do: CkSkillValidate.call(arguments)
  defp do_dispatch_tool("ck_load_resources", arguments), do: CkLoadResources.call(arguments)
  defp do_dispatch_tool("ck_mcp_discover", arguments), do: CkMcpDiscover.call(arguments)
  defp do_dispatch_tool("ck_cost_optimizer", arguments), do: CkCostOptimizer.call(arguments)

  defp do_dispatch_tool("ck_deployment_advisor", arguments),
    do: CkDeploymentAdvisor.call(arguments)

  defp do_dispatch_tool("ck_outcome_tracker", arguments), do: CkOutcomeTracker.call(arguments)
  defp do_dispatch_tool("ck_token_audit", arguments), do: CkTokenAudit.call(arguments)

  defp do_dispatch_tool(unknown, _arguments),
    do: {:error, {:invalid_arguments, "Unknown tool: #{unknown}"}}

  defp track_tool_usage(project_root, tool_name) do
    # Track usage asynchronously to avoid blocking tool calls
    Task.start(fn ->
      ControlKeel.MCP.ToolGroupTracker.track_tool_usage(project_root, tool_name)
    end)
  end

  def tool_groups, do: Map.keys(@tool_groups)

  def ck_validate_tool do
    %{
      "name" => "ck_validate",
      "description" =>
        "Validate proposed code, config, shell, or text content before execution, including trust-boundary checks for untrusted instructions and high-impact actions.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "kind" => %{"type" => "string", "enum" => ["code", "config", "shell", "text"]},
          "domain_pack" => %{"type" => "string", "enum" => Domains.supported_packs()},
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "source_type" => %{"type" => "string", "enum" => TrustBoundary.source_types()},
          "trust_level" => %{"type" => "string", "enum" => TrustBoundary.trust_levels()},
          "intended_use" => %{"type" => "string", "enum" => TrustBoundary.intended_uses()},
          "security_workflow_phase" => %{
            "type" => "string",
            "enum" => CkValidate.workflow_phase_values(),
            "description" =>
              "Canonical workflow phase. Compatibility aliases such as `preflight`, `analysis`, and `pre_edit` are accepted and normalized."
          },
          "artifact_type" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.artifact_types() ++ ["instruction", "text"],
            "description" =>
              "Canonical artifact type. Compatibility aliases `instruction` and `text` are accepted and normalized to `source`."
          },
          "target_scope" => %{
            "type" => "string",
            "enum" => SecurityWorkflow.target_scopes()
          },
          "requested_capabilities" => %{
            "type" => "array",
            "items" => %{"type" => "string", "enum" => TrustBoundary.capabilities()}
          }
        }
      }
    }
  end

  def ck_execute_code_tool do
    %{
      "name" => "ck_execute_code",
      "description" =>
        "Execute generated code only inside a configured non-local sandbox. Defaults to Docker, denies network/filesystem/secrets/shell/deploy, validates source first, and supports dry_run for planning.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["code"],
        "properties" => %{
          "code" => %{
            "type" => "string",
            "description" => "Generated source code to validate and execute in the sandbox."
          },
          "language" => %{
            "type" => "string",
            "enum" => ["javascript", "python"],
            "description" => "Runtime language. Defaults to javascript."
          },
          "sandbox" => %{
            "type" => "string",
            "enum" => ["docker"],
            "description" =>
              "Execution sandbox. Local host execution is intentionally unsupported."
          },
          "dry_run" => %{"type" => "boolean"},
          "timeout_ms" => %{"type" => ["integer", "string"]},
          "max_output_bytes" => %{"type" => ["integer", "string"]},
          "risk_tier" => %{
            "type" => "string",
            "enum" => ["low", "medium", "moderate", "high", "critical"]
          },
          "requested_capabilities" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => [
                "read_api",
                "write_api",
                "network",
                "filesystem",
                "secrets",
                "shell",
                "deploy"
              ]
            }
          },
          "network_allowlist" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          },
          "allowed_env_vars" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "List of environment variable names to expose from the host environment into the sandbox. Explicit env vars take precedence over host env vars. If empty, no host environment variables are exposed."
          },
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_context_tool do
    %{
      "name" => "ck_context",
      "description" =>
        "Fetch current mission state, governed findings, budget, proof summary, planning context, workspace snapshot, reacquisition/drift signals, recent transcript events, resume context, and ControlKeel instruction hierarchy for a session.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "detail_level" => %{
            "type" => "string",
            "enum" => ["compact", "full"],
            "description" =>
              "Use compact by default to reduce token usage; request full only when raw workspace/resume/transcript payloads are needed."
          }
        }
      }
    }
  end

  def ck_context_pack_tool do
    %{
      "name" => "ck_context_pack",
      "description" =>
        "Build a compact factual context bundle for the current session/task by combining task facts, proof state, resume highlights, memory excerpts, and citations into one agent-ready pack.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "task_id" => %{"type" => ["integer", "string"]},
          "query" => %{
            "type" => "string",
            "description" =>
              "Optional explicit retrieval query. When omitted, ControlKeel synthesizes one from the current task and session."
          },
          "top_k" => %{"type" => ["integer", "string"]},
          "detail_level" => %{"type" => "string", "enum" => ["compact", "full"]}
        }
      }
    }
  end

  def ck_observability_tool do
    %{
      "name" => "ck_observability",
      "description" =>
        "Read local observability reports for sessions, loop status, problems, memory, costs, trends, evals, generated benchmarks, history, and advisory promotion candidates. Read-only: no benchmark execution, draft approval, materialization, or promotion mutation.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "report" => %{
            "type" => "string",
            "enum" => CkObservability.reports(),
            "description" => "Report to return; defaults to overview."
          },
          "surface" => %{
            "type" => "string",
            "enum" => CkObservability.reports(),
            "description" => "Compatibility alias for report."
          },
          "session_id" => %{"type" => ["integer", "string"]},
          "workspace_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]},
          "days" => %{"type" => ["integer", "string"]},
          "stale_days" => %{"type" => ["integer", "string"]},
          "by" => %{"type" => "string", "enum" => ["model", "tool", "source", "provider"]}
        }
      }
    }
  end

  def ck_experience_index_tool do
    %{
      "name" => "ck_experience_index",
      "description" =>
        "List recent prior sessions in the same workspace and the read-only experience artifacts available for each run. " <>
          "Pass `query` for freeform keyword search across session titles, task titles, and finding descriptions — " <>
          "useful for questions like 'has this deployment pattern caused a blocked finding before?'",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "session_limit" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "same_domain_only" => %{"type" => "boolean"},
          "query" => %{
            "type" => "string",
            "description" =>
              "Freeform keyword filter applied to session title, task titles, and finding descriptions. " <>
                "All tokens must match (AND logic). Omit to return all recent sessions."
          }
        }
      }
    }
  end

  def ck_experience_read_tool do
    %{
      "name" => "ck_experience_read",
      "description" =>
        "Read one prior-run artifact such as a session summary, audit log, trace packet, or proof summary from the workspace experience archive.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["artifact_type"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "source_session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "artifact_type" => %{
            "type" => "string",
            "enum" => ["session_summary", "audit_log", "trace_packet", "proof_summary"]
          }
        }
      }
    }
  end

  def ck_experience_search_tool do
    %{
      "name" => "ck_experience_search",
      "description" =>
        "Freeform full-text search across findings and tasks within the current workspace. Returns ranked results with citations. Useful for questions like 'has this deployment pattern caused a blocked finding before?' or 'what did we do about the SQL performance issue?'",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "query" => %{
            "type" => "string",
            "description" =>
              "Freeform search query. Supports natural language and keyword search."
          },
          "limit" => %{
            "type" => ["integer", "string"],
            "description" => "Maximum number of results to return. Defaults to 10, maximum 20."
          }
        }
      }
    }
  end

  def ck_finding_tool do
    %{
      "name" => "ck_finding",
      "description" => "Persist a governed finding and return the ruling state.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "category", "severity", "rule_id", "plain_message"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "category" => %{"type" => "string"},
          "severity" => %{"type" => "string"},
          "rule_id" => %{"type" => "string"},
          "plain_message" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "decision" => %{
            "type" => "string",
            "enum" => ["allow", "warn", "block", "escalate_to_human"]
          },
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_trace_packet_tool do
    %{
      "name" => "ck_trace_packet",
      "description" =>
        "Export a structured session or task trace packet with failure patterns and eval candidates for trace-centered improvement loops.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "task_id" => %{"type" => ["integer", "string"]},
          "events_limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_failure_clusters_tool do
    %{
      "name" => "ck_failure_clusters",
      "description" =>
        "Cluster recurring failure modes across recent session traces in the same workspace and return reusable eval candidates.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "session_limit" => %{"type" => ["integer", "string"]},
          "same_domain_only" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_tool_health_tool do
    %{
      "name" => "ck_tool_health",
      "description" =>
        "Analyze governance coverage across recent sessions in the workspace — which CK governance tools (ck_validate, ck_review_submit, ck_budget, ck_memory_record, ck_goal) are load-bearing, active, low-usage, or unused — and return actionable recommendations for gaps.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "session_limit" => %{
            "type" => ["integer", "string"],
            "description" => "Number of recent sessions to analyze. Defaults to 10."
          }
        }
      }
    }
  end

  def ck_skill_evolution_tool do
    %{
      "name" => "ck_skill_evolution",
      "description" =>
        "Synthesize a deduplicated skill-evolution packet from recent traces and recurring failure clusters, including anti-patterns, reinforced practices, and a ready-to-merge skill draft.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "session_limit" => %{"type" => ["integer", "string"]},
          "same_domain_only" => %{"type" => "boolean"},
          "current_skill_name" => %{"type" => "string"},
          "current_skill_content" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_fs_ls_tool do
    %{
      "name" => "ck_fs_ls",
      "description" =>
        "List files and directories inside the bound project root through a read-only virtual workspace surface.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "path" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_fs_read_tool do
    %{
      "name" => "ck_fs_read",
      "description" =>
        "Read a file from the bound project root through the read-only virtual workspace without using a sandbox.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["path"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "start_line" => %{"type" => ["integer", "string"]},
          "max_lines" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_find_tool do
    %{
      "name" => "ck_fs_find",
      "description" =>
        "Find files or directories by path fragment inside the bound project root through the read-only virtual workspace.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "query" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_fs_grep_tool do
    %{
      "name" => "ck_fs_grep",
      "description" =>
        "Search file contents inside the bound project root through the read-only virtual workspace using grep-style semantics.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "path" => %{"type" => "string"},
          "query" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]},
          "ignore_case" => %{"type" => "boolean"},
          "fixed_strings" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_worktree_list_tool do
    %{
      "name" => "ck_worktree_list",
      "description" =>
        "List all git worktrees in the current repository with their branch, HEAD, and status information.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_worktree_switch_tool do
    %{
      "name" => "ck_worktree_switch",
      "description" =>
        "Switch the current session to a different git worktree and update session metadata accordingly.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["worktree_path"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "worktree_path" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_checkpoint_create_tool do
    %{
      "name" => "ck_checkpoint_create",
      "description" =>
        "Create a workspace checkpoint capturing git state, workspace context, and metadata for migration or rollback.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["task_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "type" => %{
            "type" => "string",
            "enum" => ["workspace_snapshot", "git_state", "dependency_state", "task_milestone"]
          },
          "summary" => %{"type" => "string"},
          "created_by" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_checkpoint_restore_tool do
    %{
      "name" => "ck_checkpoint_restore",
      "description" =>
        "Restore session state from a previous checkpoint, updating session metadata with checkpoint information.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["checkpoint_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "checkpoint_id" => %{"type" => ["integer", "string"]},
          "strict" => %{"type" => "boolean"}
        }
      }
    }
  end

  def ck_checkpoint_list_tool do
    %{
      "name" => "ck_checkpoint_list",
      "description" => "List all checkpoints for a session, optionally filtered by type.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "type" => %{
            "type" => "string",
            "enum" => ["workspace_snapshot", "git_state", "dependency_state", "task_milestone"]
          },
          "limit" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_diff_tool do
    %{
      "name" => "ck_git_diff",
      "description" =>
        "Generate a git diff between two refs and run CK validation on the diff for governed review.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{"type" => "string"},
          "base_ref" => %{"type" => "string"},
          "head_ref" => %{"type" => "string"},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_commit_tool do
    %{
      "name" => "ck_git_commit",
      "description" =>
        "Validate a commit message through CK and execute git commit if validation passes and no findings are blocked.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["message"],
        "properties" => %{
          "project_root" => %{"type" => "string"},
          "message" => %{"type" => "string"},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_git_status_tool do
    %{
      "name" => "ck_git_status",
      "description" =>
        "Get git status with CK findings correlation for the current session state.",
      "inputSchema" => %{
        "type" => "object",
        "required" => [],
        "properties" => %{
          "project_root" => %{"type" => "string"},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_monitor_subscribe_tool do
    %{
      "name" => "ck_monitor_subscribe",
      "description" =>
        "Subscribe to session events for remote monitoring via webhook. Provides read-only visibility into session activity.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["subscriber_url"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "subscriber_url" => %{"type" => "string"},
          "event_types" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "Array of event types to subscribe to. Omit for all events. Examples: task_started, task_completed, finding_created"
          }
        }
      }
    }
  end

  def ck_review_submit_tool do
    %{
      "name" => "ck_review_submit",
      "description" =>
        "Submit a governed plan, diff, or completion packet for browser review and execution gating, including recursive plan-refinement metadata for larger tasks.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["submission_body"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "title" => %{"type" => "string"},
          "review_type" => %{"type" => "string", "enum" => ["plan", "diff", "completion"]},
          "submission_body" => %{"type" => "string"},
          "annotations" => %{"type" => "object"},
          "feedback_notes" => %{"type" => "string"},
          "submitted_by" => %{"type" => "string"},
          "metadata" => %{"type" => "object"},
          "previous_review_id" => %{"type" => ["integer", "string"]},
          "plan_phase" => %{
            "type" => "string",
            "enum" => [
              "ticket",
              "research_packet",
              "design_options",
              "narrowed_decision",
              "implementation_plan",
              "code_backed_plan"
            ]
          },
          "research_summary" => %{"type" => "string"},
          "codebase_findings" => %{"type" => "array", "items" => %{"type" => "string"}},
          "prior_art_summary" => %{"type" => "string"},
          "alignment_context" => %{"type" => "array", "items" => %{"type" => "string"}},
          "consulted_roles" => %{"type" => "array", "items" => %{"type" => "string"}},
          "options_considered" => %{"type" => "array", "items" => %{"type" => "string"}},
          "selected_option" => %{"type" => "string"},
          "rejected_options" => %{"type" => "array", "items" => %{"type" => "string"}},
          "implementation_steps" => %{"type" => "array", "items" => %{"type" => "string"}},
          "validation_plan" => %{"type" => "array", "items" => %{"type" => "string"}},
          "code_snippets" => %{"type" => "array", "items" => %{"type" => "string"}},
          "scope_estimate" => %{
            "type" => "object",
            "properties" => %{
              "files_touched_estimate" => %{"type" => ["integer", "string"]},
              "diff_size_estimate" => %{"type" => ["integer", "string"]},
              "architectural_scope" => %{"type" => "boolean"}
            }
          }
        }
      }
    }
  end

  def ck_review_status_tool do
    %{
      "name" => "ck_review_status",
      "description" => "Fetch the latest status, notes, and browser URL for a submitted review.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "review_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "review_type" => %{"type" => "string", "enum" => ["plan", "diff", "completion"]}
        }
      }
    }
  end

  def ck_review_feedback_tool do
    %{
      "name" => "ck_review_feedback",
      "description" => "Approve or deny a submitted review and attach feedback or annotations.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["review_id", "decision"],
        "properties" => %{
          "review_id" => %{"type" => ["integer", "string"]},
          "decision" => %{"type" => "string", "enum" => ["approved", "denied"]},
          "feedback_notes" => %{"type" => "string"},
          "annotations" => %{"type" => "object"},
          "reviewed_by" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_regression_result_tool do
    %{
      "name" => "ck_regression_result",
      "description" =>
        "Record external regression-test evidence from systems such as Bug0 or Passmark so proof bundles and release readiness can account for it.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "engine", "flow_name", "outcome"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "engine" => %{"type" => "string"},
          "flow_name" => %{"type" => "string"},
          "outcome" => %{
            "type" => "string",
            "enum" => ["passed", "failed", "flaky", "skipped"]
          },
          "summary" => %{"type" => "string"},
          "environment" => %{"type" => "string"},
          "commit_sha" => %{"type" => "string"},
          "external_run_id" => %{"type" => "string"},
          "evidence" => %{"type" => "object"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_search_tool do
    %{
      "name" => "ck_memory_search",
      "description" =>
        "Search governed typed memory for the current session so agents can recover prior decisions, findings, and proof context explicitly.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["query"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "task_id" => %{"type" => ["integer", "string"]},
          "query" => %{"type" => "string"},
          "record_type" => %{"type" => "string", "enum" => ControlKeel.Memory.record_types()},
          "top_k" => %{"type" => ["integer", "string"]},
          "source_type" => %{"type" => "string"},
          "source_id" => %{"type" => "string"}
        }
      }
    }
  end

  def ck_memory_record_tool do
    %{
      "name" => "ck_memory_record",
      "description" =>
        "Record a governed memory note or decision for the current session so future agents can explicitly retrieve it.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["memory"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "task_id" => %{"type" => ["integer", "string"]},
          "memory" => %{
            "oneOf" => [
              %{"type" => "string"},
              %{
                "type" => "object",
                "properties" => %{
                  "content" => %{"type" => "string"},
                  "memory" => %{"type" => "string"},
                  "body" => %{"type" => "string"},
                  "title" => %{"type" => "string"},
                  "summary" => %{"type" => "string"},
                  "record_type" => %{
                    "type" => "string",
                    "enum" => ControlKeel.Memory.record_types()
                  },
                  "tags" => %{
                    "oneOf" => [
                      %{"type" => "array", "items" => %{"type" => "string"}},
                      %{"type" => "string"}
                    ]
                  },
                  "source_type" => %{"type" => "string"},
                  "source_id" => %{"type" => "string"},
                  "metadata" => %{"type" => "object"}
                }
              }
            ]
          },
          "title" => %{"type" => "string"},
          "summary" => %{"type" => "string"},
          "body" => %{"type" => "string"},
          "record_type" => %{"type" => "string", "enum" => ControlKeel.Memory.record_types()},
          "tags" => %{
            "oneOf" => [
              %{"type" => "array", "items" => %{"type" => "string"}},
              %{"type" => "string"}
            ]
          },
          "source_type" => %{"type" => "string"},
          "source_id" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_goal_tool do
    %{
      "name" => "ck_goal",
      "description" =>
        "Record, list, and update durable governed goals so long-running intent stays explicit, citable, and reviewable across sessions.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id", "mode"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "mode" => %{"type" => "string", "enum" => ["record", "list", "update_status"]},
          "goal" => %{"type" => "string"},
          "goal_id" => %{"type" => ["integer", "string"]},
          "title" => %{"type" => "string"},
          "summary" => %{"type" => "string"},
          "body" => %{"type" => "string"},
          "status" => %{
            "type" => "string",
            "enum" => ControlKeel.MCP.Tools.CkGoal.statuses() ++ ["all"]
          },
          "horizon" => %{
            "type" => "string",
            "enum" => ControlKeel.MCP.Tools.CkGoal.horizons()
          },
          "progress_note" => %{"type" => "string"},
          "limit" => %{"type" => ["integer", "string"]},
          "tags" => %{
            "oneOf" => [
              %{"type" => "array", "items" => %{"type" => "string"}},
              %{"type" => "string"}
            ]
          },
          "source_type" => %{"type" => "string"},
          "source_id" => %{"type" => "string"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  def ck_memory_archive_tool do
    %{
      "name" => "ck_memory_archive",
      "description" =>
        "Archive a memory record when it is stale, superseded, or no longer safe to surface to future agents.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["memory_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "project_root" => %{"type" => "string"},
          "memory_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  def ck_budget_tool do
    %{
      "name" => "ck_budget",
      "description" =>
        "Estimate or record the cost of an agent operation against session and daily budgets. " <>
          "Pass include_token_overhead: true with project_root to attach a token overhead audit " <>
          "(rule files, skill duplicates, tool schemas) to the budget response.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["session_id"],
        "properties" => %{
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]},
          "mode" => %{"type" => "string", "enum" => ["estimate", "commit", "status"]},
          "estimated_cost_cents" => %{"type" => ["integer", "string"]},
          "provider" => %{"type" => "string"},
          "model" => %{"type" => "string"},
          "input_tokens" => %{"type" => ["integer", "string"]},
          "cached_input_tokens" => %{"type" => ["integer", "string"]},
          "output_tokens" => %{"type" => ["integer", "string"]},
          "source" => %{"type" => "string"},
          "tool" => %{"type" => "string"},
          "metadata" => %{"type" => "object"},
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to project root. Required when include_token_overhead is true."
          },
          "include_token_overhead" => %{
            "type" => "boolean",
            "description" =>
              "When true, attach a token overhead summary (rule files, skill duplicates, tool schemas) to the response."
          }
        }
      }
    }
  end

  defp authorize_tool(name, arguments, opts) do
    case Keyword.get(opts, :authorize) do
      nil -> :ok
      fun when is_function(fun, 2) -> fun.(name, arguments)
      _ -> :ok
    end
  end

  defp ck_route_tool do
    %{
      "name" => "ck_route",
      "description" =>
        "Recommend the best AI agent for a given task, considering security tier, remaining budget, and task type.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["task"],
        "properties" => %{
          "task" => %{
            "type" => "string",
            "description" => "Plain-language description of the task to be performed"
          },
          "risk_tier" => %{
            "type" => "string",
            "enum" => ["low", "medium", "high", "critical"],
            "description" => "Security sensitivity of the task. Default: medium"
          },
          "budget_remaining_cents" => %{
            "type" => ["integer", "string"],
            "description" => "Remaining session budget in cents"
          },
          "allowed_agents" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" =>
              "Restrict routing to these agent IDs. Omit to allow all supported agents."
          }
        }
      }
    }
  end

  defp ck_delegate_tool do
    %{
      "name" => "ck_delegate",
      "description" =>
        "Ask ControlKeel to run or hand off a governed task or session to another supported agent.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{"type" => ["integer", "string"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "agent" => %{"type" => "string"},
          "mode" => %{"type" => "string", "enum" => ["auto", "embedded", "handoff", "runtime"]},
          "project_root" => %{"type" => "string"}
        }
      }
    }
  end

  defp ck_cost_optimizer_tool do
    %{
      "name" => "ck_cost_optimizer",
      "description" => "Get cost optimization suggestions or compare agent prices for a task.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["suggest", "compare"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "spending" => %{"type" => "array", "items" => %{"type" => "object"}},
          "top_provider" => %{"type" => "string"},
          "top_model" => %{"type" => "string"},
          "task_description" => %{"type" => "string"},
          "estimated_tokens" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_deployment_advisor_tool do
    %{
      "name" => "ck_deployment_advisor",
      "description" =>
        "Analyze project stack, suggest deployment platforms, and generate CI/CD/Docker files.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode", "project_root"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["analyze", "generate_files", "dns_guide"]},
          "project_root" => %{"type" => "string"},
          "dry_run" => %{"type" => "boolean"}
        }
      }
    }
  end

  defp ck_outcome_tracker_tool do
    %{
      "name" => "ck_outcome_tracker",
      "description" =>
        "Record session outcomes or get leaderboard for agents to power reinforcement learning.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["mode"],
        "properties" => %{
          "mode" => %{"type" => "string", "enum" => ["record", "get_session", "get_leaderboard"]},
          "session_id" => %{"type" => ["integer", "string"]},
          "outcome" => %{"type" => "string"},
          "agent_id" => %{"type" => "string"},
          "task_type" => %{"type" => "string"},
          "workspace_id" => %{"type" => ["integer", "string"]},
          "limit" => %{"type" => "integer"},
          "window" => %{"type" => "integer"}
        }
      }
    }
  end

  defp ck_token_audit_tool do
    %{
      "name" => "ck_token_audit",
      "description" =>
        "Audit project rule files (AGENTS.md, CLAUDE.md, etc.) and skills for token overhead. " <>
          "Returns word counts, token estimates, duplicate detection, and optimization recommendations.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Omit to use current working directory."
          },
          "mode" => %{
            "type" => "string",
            "enum" => ["full", "skills", "rules", "tools"],
            "description" =>
              "Audit mode: 'full' (rules + skills), 'skills' (skills only), 'rules' (rules only), 'tools' (CK MCP tool schemas). Defaults to 'full'."
          }
        }
      }
    }
  end

  defp ck_skill_list_tool do
    %{
      "name" => "ck_skill_list",
      "description" =>
        "List all available AgentSkills for this project. Returns names, descriptions, and scopes. " <>
          "Call this to discover capabilities you can activate, then use ck_skill_load to load a skill's full instructions.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_root" => %{
            "type" => "string",
            "description" => "Absolute path to the project root. Omit to use global skills only."
          },
          "target" => %{
            "type" => "string",
            "description" =>
              "Optional compatibility target filter, such as codex or claude-plugin."
          },
          "format" => %{
            "type" => "string",
            "enum" => ["json", "xml"],
            "description" =>
              "Response format. Use xml to receive an <available_skills> block for system prompt injection."
          },
          "include_duplicate_copies" => %{
            "type" => "boolean",
            "description" =>
              "If true, surface diagnostics for identical duplicate skill copies that MCP hosts may load (token overhead). Defaults to false."
          }
        }
      }
    }
  end

  defp ck_skill_load_tool do
    names = skill_names_for_ck_skill_load_enum()

    name_schema =
      %{
        "type" => "string",
        "description" =>
          "The skill name as returned by ck_skill_list. In MCP stdio mode, call ck_skill_list first; " <>
            "the enum is omitted so this handshake stays fast."
      }
      |> maybe_put_json_schema_enum(names)

    %{
      "name" => "ck_skill_load",
      "description" =>
        "Load the full instructions for a named AgentSkill. Returns the SKILL.md body wrapped in " <>
          "<skill_content> tags plus a list of bundled resource files. " <>
          "Call after ck_skill_list to activate a specific skill.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["name"],
        "properties" => %{
          "name" => name_schema,
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Omit to search global skills only."
          },
          "target" => %{
            "type" => "string",
            "description" => "Optional render target such as codex, claude, copilot, or cursor."
          },
          "session_id" => %{"type" => ["integer", "string"]},
          "task_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp ck_skill_validate_tool do
    %{
      "name" => "ck_skill_validate",
      "description" =>
        "Validate skill output against a JSON Schema defined in the skill's result-schema frontmatter field. " <>
          "Skills can define a result_schema in their frontmatter; agents call this tool after running a skill to enforce typed, structured output. " <>
          "Accepts output + schema directly, or output + skill_name to validate against the skill's built-in schema.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["output"],
        "properties" => %{
          "output" => %{
            "type" => "string",
            "description" =>
              "The skill output to validate. Can be a JSON string or plain text, up to 100KB."
          },
          "schema" => %{
            "type" => "string",
            "description" =>
              "JSON Schema as a string to validate against. Required if skill_name is not provided."
          },
          "skill_name" => %{
            "type" => "string",
            "description" =>
              "Optional skill name to use the skill's built-in result_schema. If provided, schema is not required."
          },
          "project_root" => %{
            "type" => "string",
            "description" =>
              "Absolute path to the project root. Only used when skill_name is provided."
          }
        }
      }
    }
  end

  defp ck_load_resources_tool do
    %{
      "name" => "ck_load_resources",
      "description" =>
        "Fallback for clients that do not support MCP resources. Load one or more CK resource URIs such as skills://<name>.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["uris"],
        "properties" => %{
          "uris" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Resource URIs to load, for example skills://controlkeel-governance"
          },
          "project_root" => %{"type" => "string"},
          "target" => %{"type" => "string"},
          "session_id" => %{"type" => ["integer", "string"]}
        }
      }
    }
  end

  defp ck_mcp_discover_tool do
    %{
      "name" => "ck_mcp_discover",
      "description" =>
        "Auto-discover tools from an external MCP server by querying its tools/list endpoint. " <>
          "This enables progressive discovery of MCP capabilities without manual configuration.",
      "inputSchema" => %{
        "type" => "object",
        "required" => ["server_url"],
        "properties" => %{
          "server_url" => %{
            "type" => "string",
            "description" =>
              "URL of the MCP server (e.g., 'http://localhost:3001/mcp' for HTTP, or a path for stdio)"
          },
          "timeout" => %{
            "type" => "integer",
            "description" => "Request timeout in milliseconds. Default: 10000"
          },
          "transport" => %{
            "type" => "string",
            "enum" => ["http", "stdio"],
            "description" =>
              "Transport type. Auto-detected from server_url if not specified. HTTP uses Erlang's built-in :httpc (no extra dependencies)."
          }
        }
      }
    }
  end

  defp current_skill_names do
    Registry.names(stdio_project_root(), trust_project_skills: true)
  end

  defp current_skills do
    Registry.catalog(stdio_project_root(), trust_project_skills: true)
  end

  defp stdio_project_root do
    case System.get_env("CK_PROJECT_ROOT") do
      v when is_binary(v) and v != "" ->
        v |> String.trim() |> Path.expand()

      _ ->
        File.cwd!()
    end
  end

  defp resource_schemas(_opts) do
    if mcp_stdio_mode?() do
      # Same Registry.catalog walk as tools/list — defer discovery to ck_skill_list /
      # ck_load_resources so resources/list stays instant under CK_MCP_MODE.
      []
    else
      Enum.map(current_skills(), fn skill ->
        %{
          "uri" => "skills://#{skill.name}",
          "name" => skill.name,
          "title" => skill.name,
          "description" => skill.description,
          "mimeType" => "text/markdown"
        }
      end)
    end
  end

  defp mcp_stdio_mode? do
    System.get_env("CK_MCP_MODE") in ~w(1 true TRUE yes YES)
  end

  # Determines active tool groups from env var or Application config.
  # Priority: CK_TOOL_GROUPS env var > config :controlkeel, :mcp, tool_groups: > :all
  # Example env var: CK_TOOL_GROUPS=core,governance
  # Example config:  config :controlkeel, :mcp, tool_groups: ["core", "governance"]
  defp env_tool_groups do
    case System.get_env("CK_TOOL_GROUPS") do
      v when is_binary(v) and v != "" ->
        groups =
          v
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        if groups == [], do: app_config_tool_groups(), else: groups

      _ ->
        app_config_tool_groups()
    end
  end

  defp app_config_tool_groups do
    case Application.get_env(:controlkeel, :mcp, [])[:tool_groups] do
      groups when is_list(groups) and groups != [] -> groups
      # Return nil to let adaptive mode handle it
      _ -> nil
    end
  end

  # Adaptive tool group selection based on project usage patterns.
  # Wrapped in safe calls because the MCP server starts before the deferred
  # boot task finishes starting Repo, ToolGroupTracker, etc.  A tools/list
  # request that arrives during that window must fall through to
  # smart_default_groups/1 instead of crashing the GenServer.
  defp adaptive_tool_groups(project_root) do
    # First, check if project has explicit tool group preferences
    case safe_get_project_tool_groups(project_root) do
      groups when is_list(groups) ->
        # Use project's explicit preference
        groups

      _ ->
        # No explicit preference, check usage data
        case safe_suggest_groups(project_root) do
          %{suggested: groups} when length(groups) > 2 ->
            # We have meaningful usage data, use suggested groups
            groups

          _ ->
            # No usage data yet, use smart defaults based on project type
            smart_default_groups(project_root)
        end
    end
  end

  defp safe_get_project_tool_groups(project_root) do
    ControlKeel.ProjectBinding.get_tool_groups(project_root)
  catch
    :exit, _ -> nil
  end

  defp safe_suggest_groups(project_root) do
    ControlKeel.MCP.ToolGroupTracker.suggest_groups(project_root)
  catch
    :exit, _ -> nil
  end

  # Smart default groups based on project characteristics
  defp smart_default_groups(project_root) do
    # Detect project type and suggest appropriate groups
    has_git = File.exists?(Path.join(project_root, ".git"))
    has_tests = test_dir_exists?(project_root)
    has_package_json = File.exists?(Path.join(project_root, "package.json"))
    has_mix_exs = File.exists?(Path.join(project_root, "mix.exs"))
    has_cargo_toml = File.exists?(Path.join(project_root, "Cargo.toml"))

    base_groups = ["core", "governance"]

    additional_groups =
      cond do
        # Elixir/Phoenix project - likely needs filesystem tools
        has_mix_exs -> ["filesystem", "git"]
        # Node.js project - likely needs filesystem tools
        has_package_json -> ["filesystem", "git"]
        # Rust project - likely needs filesystem tools
        has_cargo_toml -> ["filesystem", "git"]
        # Has tests - likely needs filesystem and git
        has_tests and has_git -> ["filesystem", "git"]
        # Git repo - add git tools
        has_git -> ["git"]
        # Default - add filesystem for general development
        true -> ["filesystem"]
      end

    Enum.uniq(base_groups ++ additional_groups)
  end

  defp test_dir_exists?(project_root) do
    ["test", "tests", "__tests__", "spec"]
    |> Enum.any?(fn dir -> File.dir?(Path.join(project_root, dir)) end)
  end

  # Log tool group decisions for transparency and debugging
  defp log_tool_group_decision(project_root, groups, total_tools, filtered_tools) do
    excluded_count = total_tools - filtered_tools

    Logger.info(
      "Adaptive tool groups for #{Path.basename(project_root)}: #{inspect(groups)} " <>
        "(#{filtered_tools}/#{total_tools} tools, #{excluded_count} excluded)"
    )
  end

  defp skill_names_for_ck_skill_load_enum do
    if mcp_stdio_mode?() do
      []
    else
      current_skill_names()
    end
  end

  defp maybe_put_json_schema_enum(schema, []), do: schema

  defp maybe_put_json_schema_enum(schema, names) when is_list(names) do
    Map.put(schema, "enum", names)
  end

  defp load_resource(uri, params) do
    CkLoadResources.load_resource_uri(
      uri,
      Map.get(params, "project_root"),
      Map.get(params, "target"),
      Map.get(params, "session_id")
    )
  end

  defp tool_response(id, {:ok, result}) do
    ok_response(id, %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(result)}],
      "structuredContent" => result
    })
  end

  defp tool_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  defp tool_response(id, {:error, reason}), do: error_response(id, -32000, inspect(reason))

  defp resource_response(id, {:ok, result}) do
    ok_response(id, %{
      "contents" => [
        %{
          "uri" => result["uri"],
          "mimeType" => result["mimeType"],
          "text" => result["text"]
        }
      ]
    })
  end

  defp resource_response(id, {:error, {:invalid_arguments, reason}}),
    do: error_response(id, -32602, reason)

  defp resource_response(id, {:error, reason}), do: error_response(id, -32000, inspect(reason))

  defp negotiate_mcp_protocol_version(v) when is_binary(v) and v != "" do
    if v in supported_mcp_protocol_versions(), do: v, else: default_mcp_protocol_version()
  end

  defp negotiate_mcp_protocol_version(_), do: default_mcp_protocol_version()

  defp supported_mcp_protocol_versions, do: ~w(2024-11-05 2025-03-26 2025-06-18)

  defp default_mcp_protocol_version, do: "2024-11-05"

  defp mcp_stdio_boot_gate(id) do
    case await_mcp_backend_ready(mcp_boot_gate_wait_ms()) do
      :ready ->
        :ok

      :booting ->
        {:error,
         error_response(
           id,
           -32002,
           "ControlKeel backend is still starting (Repo and services); retry shortly."
         )}

      {:failed, reason} ->
        {:error,
         error_response(
           id,
           -32003,
           "ControlKeel failed to boot: #{inspect(reason)}"
         )}

      _ ->
        :ok
    end
  end

  defp await_mcp_backend_ready(timeout_ms) when is_integer(timeout_ms) and timeout_ms <= 0 do
    normalize_mcp_backend_status(ControlKeel.Application.mcp_backend_boot_status())
  end

  defp await_mcp_backend_ready(timeout_ms) when is_integer(timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    await_mcp_backend_ready_until(deadline_ms)
  end

  defp await_mcp_backend_ready(_timeout_ms), do: :ready

  defp await_mcp_backend_ready_until(deadline_ms) do
    case normalize_mcp_backend_status(ControlKeel.Application.mcp_backend_boot_status()) do
      :booting ->
        if System.monotonic_time(:millisecond) < deadline_ms do
          Process.sleep(25)
          await_mcp_backend_ready_until(deadline_ms)
        else
          :booting
        end

      other ->
        other
    end
  end

  defp normalize_mcp_backend_status(:ready), do: :ready
  defp normalize_mcp_backend_status(:booting), do: :booting
  defp normalize_mcp_backend_status({:failed, _reason} = failed), do: failed
  defp normalize_mcp_backend_status(_status), do: :ready

  defp mcp_boot_gate_wait_ms do
    case Application.get_env(:controlkeel, :mcp_boot_gate_wait_ms, 2000) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 2000
    end
  end

  defp ok_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end
end
