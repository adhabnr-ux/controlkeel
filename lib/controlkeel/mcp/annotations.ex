defmodule ControlKeel.MCP.Annotations do
  @moduledoc """
  MCP tool annotations (`readOnlyHint` / `destructiveHint` / `idempotentHint`) so hosts
  and agents can tier permissions from machine-readable metadata instead of parsing prose.

  Conservative by design: a tool is marked `readOnlyHint: true` ONLY when it is known to
  have no side effects. Anything uncertain is left non-read-only, so a writing tool is
  never advertised as safe (the dangerous direction). `destructiveHint` is an explicit
  allowlist of state-replacing/irreversible tools. The annotations test enforces the
  invariant that no write-scoped tool (per ProtocolInterop) is ever marked read-only.

  This is intentionally a curated subset — the ~30 tools below are the ones whose
  read-only nature is unambiguous. Extending coverage to all 56 tools should go through
  a reviewed tool->capability table (tracked as follow-up), not a fragile heuristic.
  """

  # Pure-read tools: no DB/file/process mutation, no network egress with side effects.
  @read_only ~w(
    ck_context ck_context_pack ck_observability ck_experience_index ck_experience_read
    ck_experience_search ck_trace_packet ck_failure_clusters ck_tool_health
    ck_skill_evolution ck_fs_ls ck_fs_read ck_fs_find ck_fs_grep ck_git_diff
    ck_git_status ck_review_status ck_memory_search ck_route ck_cost_optimizer
    ck_token_audit ck_result_peek ck_skill_list ck_skill_validate
    ck_worktree_list ck_checkpoint_list ck_load_resources
    ck_validate ck_mcp_discover ck_skill_load
  )

  # Tools not in @read_only but with known read-only modes — conservatively left unclassified
  # because they also expose write/generate modes. Tools with only write semantics remain
  # the default (readOnlyHint: false, destructiveHint: false):
  #   ck_goal (record/update_status modes), ck_session_digest (generate mode),
  #   ck_deployment_advisor (generate_files mode), ck_checkpoint_create, ck_monitor_subscribe,
  #   ck_task, ck_session, ck_budget, ck_outcome_tracker, ck_workspace_agent,
  #   ck_copilot, ck_external_service, ck_delegate, ck_execute_code, ck_attach.

  # Tools that replace or discard state irreversibly (destructiveHint only meaningful
  # when readOnlyHint is false).
  @destructive ~w(ck_rollback ck_checkpoint_restore ck_git_commit ck_worktree_switch)

  @doc "List of tool names CK advertises as read-only (no side effects)."
  def read_only_tools, do: @read_only

  @doc """
  Annotation map for a tool. Read-only tools are also idempotent; everything else is
  conservatively treated as non-read-only and non-idempotent unless explicitly destructive.
  """
  def for_tool(name) do
    read_only? = name in @read_only

    %{
      "readOnlyHint" => read_only?,
      "destructiveHint" => name in @destructive,
      "idempotentHint" => read_only?
    }
  end
end
