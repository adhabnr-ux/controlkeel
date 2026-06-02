defmodule ControlKeel.CLI do
  @moduledoc false

  # IMPORTANT: run_command/2 clauses are intentionally organized by functionality
  # (skills, deploy, observability, etc.) rather than grouped together for maintainability
  # in this large 7000+ line module. The compiler warning about clause grouping is expected
  # and acceptable. Grouping all 50+ run_command clauses together would harm maintainability.

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

  @init_switches [
    project_root: :string,
    industry: :string,
    agent: :string,
    idea: :string,
    features: :string,
    budget: :string,
    users: :string,
    data: :string,
    project_name: :string,
    no_attach: :boolean
  ]
  @attach_switches [
    project_root: :string,
    mcp_only: :boolean,
    no_native: :boolean,
    with_skills: :boolean,
    scope: :string
  ]
  @status_switches [format: :string, json: :boolean]
  @doctor_switches [project_root: :string, format: :string, json: :boolean]
  @capabilities_switches [format: :string, json: :boolean]
  @update_switches [
    apply: :boolean,
    sync_attached: :boolean,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @context_switches [
    session_id: :integer,
    task_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]

  @validate_switches [
    content: :string,
    kind: :string,
    path: :string,
    session_id: :integer,
    task_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @findings_switches [severity: :string, status: :string, format: :string]
  @findings_translate_switches [session_id: :integer, severity: :string]
  @proofs_switches [
    session_id: :integer,
    task_id: :integer,
    deploy_ready: :boolean,
    format: :string
  ]
  @mcp_switches [project_root: :string]
  @me_switches [
    session_id: :integer,
    format: :string,
    json: :boolean,
    project_root: :string
  ]
  @memory_search_switches [session_id: :integer, type: :string]
  @deploy_analyze_switches [project_root: :string]
  @deploy_cost_switches [
    stack: :string,
    tier: :string,
    needs_db: :boolean,
    db_tier: :string,
    bandwidth: :integer,
    storage: :integer
  ]
  @cost_optimize_switches [session_id: :integer, provider: :string, model: :string]
  @cost_compare_switches [tokens: :integer]
  @precommit_check_switches [project_root: :string, domain_pack: :string, enforce: :boolean]
  @progress_switches [session_id: :integer, format: :string]
  @circuit_breaker_switches [agent_id: :string]
  @skills_list_switches [project_root: :string, target: :string, format: :string, json: :boolean]
  @skills_validate_switches [project_root: :string]
  @skills_export_switches [project_root: :string, target: :string, scope: :string]
  @skills_install_switches [project_root: :string, target: :string, scope: :string]
  @skills_doctor_switches [project_root: :string]
  @token_audit_switches [mode: :string, format: :string, project_root: :string]
  @tool_groups_suggest_switches [project_root: :string, format: :string, apply: :boolean]
  @benchmark_run_switches [
    suite: :string,
    subjects: :string,
    baseline_subject: :string,
    scenario_slugs: :string,
    domain_pack: :string
  ]
  @benchmark_list_switches [domain_pack: :string, format: :string]
  @benchmark_export_switches [format: :string]
  @watch_switches [interval: :integer, status: :boolean]
  @obs_switches [
    by: :string,
    days: :integer,
    format: :string,
    json: :boolean,
    limit: :integer,
    stale_days: :integer,
    suite: :string,
    subjects: :string,
    baseline_subject: :string,
    scenario_slugs: :string,
    dry_run: :boolean,
    execute: :boolean
  ]
  @obs_import_switches [dry_run: :boolean, persist: :boolean, format: :string, json: :boolean]
  @obs_workshop_switches [dry_run: :boolean, format: :string, json: :boolean]
  @audit_log_switches [format: :string]
  @service_account_create_switches [workspace_id: :integer, name: :string, scopes: :string]
  @service_account_list_switches [workspace_id: :integer]
  @policy_set_create_switches [
    name: :string,
    scope: :string,
    description: :string,
    rules_file: :string
  ]
  @policy_set_list_switches [workspace_id: :integer]
  @policy_set_apply_switches [precedence: :integer]
  @webhook_create_switches [
    workspace_id: :integer,
    name: :string,
    url: :string,
    events: :string,
    secret: :string
  ]
  @webhook_list_switches [workspace_id: :integer]
  @worker_start_switches [service_account_token: :string, interval: :integer]
  @provider_default_switches [scope: :string, project_root: :string]
  @provider_set_key_switches [value: :string]
  @provider_set_base_url_switches [value: :string]
  @provider_set_model_switches [value: :string]
  @provider_show_switches [project_root: :string]
  @provider_list_switches [project_root: :string]
  @provider_doctor_switches [project_root: :string]
  @bootstrap_switches [project_root: :string, ephemeral_ok: :boolean, agent: :string]
  @setup_switches [project_root: :string, ephemeral_ok: :boolean, agent: :string]
  @runtime_export_switches [project_root: :string]
  @review_diff_switches [
    base: :string,
    head: :string,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_pr_switches [
    patch: :string,
    url: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_socket_switches [
    report: :string,
    stdin: :boolean,
    session_id: :integer,
    domain_pack: :string,
    project_root: :string
  ]
  @review_plan_submit_switches [
    session_id: :integer,
    task_id: :integer,
    body_file: :string,
    stdin: :boolean,
    title: :string,
    submitted_by: :string,
    project_root: :string,
    json: :boolean
  ]
  @review_plan_open_switches [id: :integer, project_root: :string, json: :boolean]
  @review_plan_wait_switches [
    id: :integer,
    timeout: :integer,
    interval_ms: :integer,
    project_root: :string,
    json: :boolean
  ]
  @review_plan_respond_switches [
    decision: :string,
    feedback_notes: :string,
    reviewed_by: :string,
    annotations: :string,
    project_root: :string,
    json: :boolean
  ]
  @release_ready_switches [
    session_id: :integer,
    sha: :string,
    smoke_status: :string,
    artifact_source: :string,
    provenance_verified: :boolean,
    project_root: :string
  ]
  @govern_install_switches [project_root: :string]
  @govern_bind_github_switches [
    workspace_id: :integer,
    owner: :string,
    repo: :string,
    default_branch: :string,
    installation_id: :string
  ]
  @govern_unbind_github_switches [
    workspace_id: :integer,
    owner: :string,
    repo: :string
  ]
  @govern_list_github_switches [workspace_id: :integer]
  @plugin_switches [project_root: :string, scope: :string, mode: :string]
  @agents_doctor_switches [project_root: :string]
  @cloud_doctor_switches [project_root: :string]
  @cloud_connect_switches [
    project_root: :string,
    rotate: :boolean,
    enroll: :string,
    name: :string,
    invite: :string
  ]
  @cloud_sync_push_switches [project_root: :string, workspace: :string]
  @cloud_sync_pull_switches [project_root: :string, workspace: :string]
  @cloud_sync_migrate_switches [project_root: :string]
  @telemetry_status_switches [project_root: :string]
  @telemetry_enable_switches [project_root: :string, level: :string]
  @telemetry_disable_switches [project_root: :string]
  @telemetry_queue_switches [project_root: :string, limit: :integer]
  @telemetry_flush_switches [project_root: :string, limit: :integer]
  @mcp_registry_list_switches [project_root: :string]
  @mcp_registry_check_switches [project_root: :string, attested: :boolean]
  @mcp_guardrails_switches [project_root: :string]
  @user_create_switches [project_root: :string, email: :string, name: :string]
  @org_create_switches [project_root: :string, name: :string, slug: :string]
  @org_list_switches [project_root: :string]
  @org_budget_set_switches [project_root: :string, cents: :integer, clear: :boolean]
  @org_budget_show_switches [project_root: :string]
  @org_invite_switches [project_root: :string, email: :string, role: :string]
  @org_members_switches [project_root: :string]
  @org_idp_set_switches [
    project_root: :string,
    type: :string,
    issuer: :string,
    client_id: :string,
    entity_id: :string,
    idp_metadata_url: :string,
    clear: :boolean
  ]
  @org_idp_show_switches [project_root: :string]
  @run_cloud_agent_switches [
    project_root: :string,
    runtime: :string,
    budget_cents: :integer,
    scopes: :string,
    note: :string,
    user_id: :integer,
    repo_url: :string,
    branch: :string,
    commit_sha: :string,
    dispatch: :boolean
  ]
  @eval_list_switches [project_root: :string]
  @eval_run_switches [project_root: :string, suite: :string]
  @audit_export_switches [
    project_root: :string,
    workspace: :string,
    org: :string,
    since: :string,
    until: :string,
    out: :string,
    template: :string,
    sign: :boolean,
    signing_key_env: :string
  ]
  @baseline_compute_switches [workspace_id: :integer, window_days: :integer]
  @workspace_tool_policy_get_switches [workspace_id: :integer]
  @workspace_tool_policy_set_switches [workspace_id: :integer, mode: :string, tools: :string]
  @selfhost_switches [project_root: :string]
  @selfhost_pack_switches [project_root: :string, output: :string]
  @agents_discover_switches [
    project_root: :string,
    max_depth: :integer,
    json: :boolean
  ]
  @agents_list_switches [project_root: :string, format: :string, json: :boolean]
  @route_agent_switches [
    task: :string,
    risk_tier: :string,
    budget_remaining_cents: :integer,
    allowed_agents: :string,
    domain_pack: :string,
    format: :string,
    json: :boolean
  ]
  @task_claim_switches [execution_mode: :string]
  @task_heartbeat_switches [progress: :integer, note: :string]
  @task_checks_switches [checks: :string]
  @task_report_switches [status: :string, output: :string, metadata: :string]
  @agent_run_switches [project_root: :string, agent: :string, mode: :string, sandbox: :string]

  def standalone_argv do
    cond do
      standalone_wrapper_runtime?() ->
        plain_arguments()

      Code.ensure_loaded?(Burrito.Util.Args) and function_exported?(Burrito.Util.Args, :argv, 0) ->
        Burrito.Util.Args.argv()

      true ->
        System.argv()
    end
  end

  def parse(argv) when is_list(argv) do
    case scoped_help_args(argv) do
      {:help, args} ->
        {:ok, %{command: :help, options: %{}, args: args}}

      :not_help ->
        parse_command(argv)
    end
  end

  defp scoped_help_args([flag]) when flag in ["--help", "-h"], do: {:help, []}

  defp scoped_help_args(argv) do
    if Enum.any?(argv, &(&1 in ["--help", "-h"])) do
      args = Enum.reject(argv, &(&1 in ["--help", "-h"]))
      {:help, args}
    else
      :not_help
    end
  end

  defp parse_command(argv) do
    case argv do
      [] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["--help"] ->
        {:ok, %{command: :help, options: %{}, args: []}}

      ["-h"] ->
        {:ok, %{command: :help, options: %{}, args: []}}

      ["--version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["-V"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["-v"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["serve"] ->
        {:ok, %{command: :serve, options: %{}, args: []}}

      ["doctor" | rest] ->
        parse_with_switches(:doctor, rest, @doctor_switches)

      ["capabilities" | rest] ->
        parse_with_switches(:capabilities, rest, @capabilities_switches)

      ["me" | rest] ->
        parse_with_switches(:me, rest, @me_switches)

      ["init" | rest] ->
        parse_with_switches(:init, rest, @init_switches)

      ["setup" | rest] ->
        parse_with_switches(:setup, rest, @setup_switches)

      ["attach", "doctor" | rest] ->
        parse_with_switches(:attach_doctor, rest, @agents_doctor_switches)

      ["attach", agent | rest] ->
        if agent in AgentIntegration.attachable_ids() do
          parse_attach(agent, rest)
        else
          {:error, usage_text()}
        end

      ["runtime", "export", runtime_id | rest] ->
        parse_runtime_export(runtime_id, rest)

      ["review", "diff" | rest] ->
        parse_with_switches(:review_diff, rest, @review_diff_switches)

      ["review", "pr" | rest] ->
        parse_with_switches(:review_pr, rest, @review_pr_switches)

      ["review", "socket" | rest] ->
        parse_with_switches(:review_socket, rest, @review_socket_switches)

      ["review", "plan", "submit" | rest] ->
        parse_with_switches(:review_plan_submit, rest, @review_plan_submit_switches)

      ["review", "plan", "open" | rest] ->
        parse_with_switches(:review_plan_open, rest, @review_plan_open_switches)

      ["review", "plan", "wait" | rest] ->
        parse_with_switches(:review_plan_wait, rest, @review_plan_wait_switches)

      ["review", "plan", "respond", review_id | rest] ->
        parse_review_plan_respond(review_id, rest)

      ["release-ready" | rest] ->
        parse_with_switches(:release_ready, rest, @release_ready_switches)

      ["govern", "install", "github" | rest] ->
        parse_with_switches(:govern_install_github, rest, @govern_install_switches)

      ["govern", "bind", "github" | rest] ->
        parse_with_switches(:govern_bind_github, rest, @govern_bind_github_switches)

      ["govern", "unbind", "github" | rest] ->
        parse_with_switches(:govern_unbind_github, rest, @govern_unbind_github_switches)

      ["govern", "list", "github" | rest] ->
        parse_with_switches(:govern_list_github, rest, @govern_list_github_switches)

      ["plugin", "export", plugin | rest] ->
        parse_plugin_command(:plugin_export, plugin, rest)

      ["plugin", "install", plugin | rest] ->
        parse_plugin_command(:plugin_install, plugin, rest)

      ["agents", "doctor" | rest] ->
        parse_with_switches(:agents_doctor, rest, @agents_doctor_switches)

      ["cloud", "doctor" | rest] ->
        parse_with_switches(:cloud_doctor, rest, @cloud_doctor_switches)

      ["cloud", "connect" | rest] ->
        parse_with_switches(:cloud_connect, rest, @cloud_connect_switches)

      ["cloud", "push" | rest] ->
        parse_with_switches(:cloud_sync_push, rest, @cloud_sync_push_switches)

      ["cloud", "pull" | rest] ->
        parse_with_switches(:cloud_sync_pull, rest, @cloud_sync_pull_switches)

      ["cloud", "migrate" | rest] ->
        parse_with_switches(:cloud_sync_migrate, rest, @cloud_sync_migrate_switches)

      ["telemetry", "status" | rest] ->
        parse_with_switches(:telemetry_status, rest, @telemetry_status_switches)

      ["telemetry", "enable" | rest] ->
        parse_with_switches(:telemetry_enable, rest, @telemetry_enable_switches)

      ["telemetry", "disable" | rest] ->
        parse_with_switches(:telemetry_disable, rest, @telemetry_disable_switches)

      ["telemetry", "queue" | rest] ->
        parse_with_switches(:telemetry_queue, rest, @telemetry_queue_switches)

      ["telemetry", "flush" | rest] ->
        parse_with_switches(:telemetry_flush, rest, @telemetry_flush_switches)

      ["mcp", "registry", "list" | rest] ->
        parse_with_switches(:mcp_registry_list, rest, @mcp_registry_list_switches)

      ["mcp", "guardrails", "list" | rest] ->
        parse_with_switches(:mcp_guardrails_list, rest, @mcp_guardrails_switches)

      ["user", "create" | rest] ->
        parse_with_switches(:user_create, rest, @user_create_switches)

      ["org", "create" | rest] ->
        parse_with_switches(:org_create, rest, @org_create_switches)

      ["org", "list" | rest] ->
        parse_with_switches(:org_list, rest, @org_list_switches)

      ["org", "budget", "set", slug | rest] ->
        case parse_with_switches(:org_budget_set, rest, @org_budget_set_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "budget", "show", slug | rest] ->
        case parse_with_switches(:org_budget_show, rest, @org_budget_show_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "invite", slug | rest] ->
        case parse_with_switches(:org_invite, rest, @org_invite_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "members", slug | rest] ->
        case parse_with_switches(:org_members, rest, @org_members_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "idp", "set", slug | rest] ->
        case parse_with_switches(:org_idp_set, rest, @org_idp_set_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["org", "idp", "show", slug | rest] ->
        case parse_with_switches(:org_idp_show, rest, @org_idp_show_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [slug])}
          err -> err
        end

      ["mcp", "registry", "check", server_name | rest] ->
        case parse_with_switches(:mcp_registry_check, rest, @mcp_registry_check_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [server_name])}
          err -> err
        end

      ["agents", "list" | rest] ->
        parse_with_switches(:agents_list, rest, @agents_list_switches)

      ["route-agent" | rest] ->
        parse_with_switches(:route_agent, rest, @route_agent_switches)

      ["task", "complete", task_id] ->
        {:ok, %{command: :task_complete, options: %{}, args: [task_id]}}

      ["task", "claim", task_id | rest] ->
        parse_task_command(:task_claim, task_id, rest, @task_claim_switches)

      ["task", "heartbeat", task_id | rest] ->
        parse_task_command(:task_heartbeat, task_id, rest, @task_heartbeat_switches)

      ["task", "checks", task_id | rest] ->
        parse_task_command(:task_checks, task_id, rest, @task_checks_switches)

      ["task", "report", task_id | rest] ->
        parse_task_command(:task_report, task_id, rest, @task_report_switches)

      ["run", "task", task_id | rest] ->
        parse_run_command(:run_task, task_id, rest)

      ["run", "cloud-agent", task_id | rest] ->
        case parse_with_switches(:run_cloud_agent, rest, @run_cloud_agent_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [task_id])}
          err -> err
        end

      ["eval", "list" | rest] ->
        parse_with_switches(:eval_list, rest, @eval_list_switches)

      ["eval", "run" | rest] ->
        parse_with_switches(:eval_run, rest, @eval_run_switches)

      ["audit", "export" | rest] ->
        parse_with_switches(:audit_export, rest, @audit_export_switches)

      ["workspace", "tool-policy", "get" | rest] ->
        parse_with_switches(:workspace_tool_policy_get, rest, @workspace_tool_policy_get_switches)

      ["workspace", "tool-policy", "set" | rest] ->
        parse_with_switches(:workspace_tool_policy_set, rest, @workspace_tool_policy_set_switches)

      ["baseline", "compute" | rest] ->
        parse_with_switches(:baseline_compute, rest, @baseline_compute_switches)

      ["selfhost", "pack" | rest] ->
        parse_with_switches(:selfhost_pack, rest, @selfhost_pack_switches)

      ["selfhost", "verify" | rest] ->
        parse_with_switches(:selfhost_verify, rest, @selfhost_switches)

      ["selfhost", "manifest" | rest] ->
        parse_with_switches(:selfhost_manifest, rest, @selfhost_switches)

      ["selfhost", "install-guide" | rest] ->
        parse_with_switches(:selfhost_install_guide, rest, @selfhost_switches)

      ["agents", "discover", path | rest] ->
        case parse_with_switches(:agents_discover, rest, @agents_discover_switches) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :args, [path])}
          err -> err
        end

      ["run", "session", session_id | rest] ->
        parse_run_command(:run_session, session_id, rest)

      ["session", "list"] ->
        {:ok, %{command: :session_list, options: %{}, args: []}}

      ["session", "switch", session_id] ->
        {:ok, %{command: :session_switch, options: %{}, args: [session_id]}}

      ["registry", "sync", "acp"] ->
        {:ok, %{command: :registry_sync_acp, options: %{}, args: []}}

      ["registry", "status", "acp"] ->
        {:ok, %{command: :registry_status_acp, options: %{}, args: []}}

      ["sandbox", "status"] ->
        {:ok, %{command: :sandbox_status, options: %{}, args: []}}

      ["sandbox", "config", adapter] ->
        {:ok, %{command: :sandbox_config, options: %{adapter: adapter}, args: []}}

      ["sandbox", "config"] ->
        {:ok, %{command: :sandbox_status, options: %{}, args: []}}

      ["status" | rest] ->
        parse_with_switches(:status, rest, @status_switches)

      ["obs"] ->
        parse_with_switches(:obs_status, [], @obs_switches)

      ["obs", "status" | rest] ->
        parse_with_switches(:obs_status, rest, @obs_switches)

      ["obs", "loop" | rest] ->
        parse_with_switches(:obs_loop_status, rest, @obs_switches)

      ["obs", "loop-status" | rest] ->
        parse_with_switches(:obs_loop_status, rest, @obs_switches)

      ["obs", "problems" | rest] ->
        parse_with_switches(:obs_problems, rest, @obs_switches)

      ["obs", "costs" | rest] ->
        parse_with_switches(:obs_costs, rest, @obs_switches)

      ["obs", "imports" | rest] ->
        parse_with_switches(:obs_imports, rest, @obs_switches)

      ["obs", "trends" | rest] ->
        parse_with_switches(:obs_trends, rest, @obs_switches)

      ["obs", "regressions" | rest] ->
        parse_with_switches(:obs_regressions, rest, @obs_switches)

      ["obs", "recommend" | rest] ->
        parse_with_switches(:obs_recommend, rest, @obs_switches)

      ["obs", "evals", "save" | rest] ->
        parse_with_switches(:obs_evals_save, rest, @obs_switches)

      ["obs", "evals", "persisted" | rest] ->
        parse_with_switches(:obs_evals_persisted, rest, @obs_switches)

      ["obs", "evals" | rest] ->
        parse_with_switches(:obs_evals, rest, @obs_switches)

      ["obs", "benchmarks", "draft" | rest] ->
        parse_with_switches(:obs_benchmark_draft, rest, @obs_switches)

      ["obs", "benchmarks", "approve", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_approve, draft_id, rest)

      ["obs", "benchmarks", "reject", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_reject, draft_id, rest)

      ["obs", "benchmarks", "archive", draft_id | rest] ->
        parse_obs_benchmark_status(:obs_benchmark_archive, draft_id, rest)

      ["obs", "benchmarks", "drafts" | rest] ->
        parse_with_switches(:obs_benchmark_drafts, rest, @obs_switches)

      ["obs", "benchmarks", "materialize" | rest] ->
        parse_with_switches(:obs_benchmark_materialize, rest, @obs_switches)

      ["obs", "benchmarks", "scenarios" | rest] ->
        parse_with_switches(:obs_benchmark_scenarios, rest, @obs_switches)

      ["obs", "benchmarks", "run" | rest] ->
        parse_with_switches(:obs_benchmark_run, rest, @obs_switches)

      ["obs", "benchmarks", "history" | rest] ->
        parse_with_switches(:obs_benchmark_history, rest, @obs_switches)

      ["obs", "promotions" | rest] ->
        parse_with_switches(:obs_promotions, rest, @obs_switches)

      ["obs", "compare" | rest] ->
        parse_with_switches(:obs_compare, rest, @obs_switches)

      ["obs", "timeline" | rest] ->
        parse_obs_timeline(rest)

      ["obs", "memory-quality" | rest] ->
        parse_with_switches(:obs_memory_quality, rest, @obs_switches)

      ["obs", "memory" | rest] ->
        parse_obs_memory(rest)

      ["obs", "export", session_id | rest] ->
        parse_obs_session_command(:obs_export, session_id, rest)

      ["obs", "import", file_path | rest] ->
        parse_obs_import(file_path, rest)

      ["obs", "workshop", file_path | rest] ->
        parse_obs_workshop(file_path, rest)

      ["obs", "run", session_id | rest] ->
        parse_obs_run(session_id, rest)

      ["context" | rest] ->
        parse_with_switches(:context, rest, @context_switches)

      ["validate" | rest] ->
        parse_with_switches(:validate, rest, @validate_switches)

      ["findings", "translate" | rest] ->
        parse_with_switches(:findings_translate, rest, @findings_translate_switches)

      ["findings" | rest] ->
        parse_with_switches(:findings, rest, @findings_switches)

      ["approve", finding_id] ->
        {:ok, %{command: :approve, options: %{}, args: [finding_id]}}

      ["proofs" | rest] ->
        parse_with_switches(:proofs, rest, @proofs_switches)

      ["proof", id] ->
        {:ok, %{command: :proof, options: %{}, args: [id]}}

      ["audit-log", session_id | rest] ->
        parse_audit_log(session_id, rest)

      ["pause", task_id] ->
        {:ok, %{command: :pause, options: %{}, args: [task_id]}}

      ["resume", task_id] ->
        {:ok, %{command: :resume, options: %{}, args: [task_id]}}

      ["memory", "search", query | rest] ->
        parse_memory_search(query, rest)

      ["skills", "list" | rest] ->
        parse_with_switches(:skills_list, rest, @skills_list_switches)

      ["skills", "validate" | rest] ->
        parse_with_switches(:skills_validate, rest, @skills_validate_switches)

      ["skills", "export" | rest] ->
        parse_skills_subcommand(:skills_export, rest, @skills_export_switches)

      ["skills", "install" | rest] ->
        parse_skills_subcommand(:skills_install, rest, @skills_install_switches)

      ["skills", "doctor" | rest] ->
        parse_with_switches(:skills_doctor, rest, @skills_doctor_switches)

      ["token", "audit" | rest] ->
        parse_with_switches(:token_audit, rest, @token_audit_switches)

      ["tool", "groups", "suggest" | rest] ->
        parse_with_switches(:tool_groups_suggest, rest, @tool_groups_suggest_switches)

      ["benchmark", "list" | rest] ->
        parse_with_switches(:benchmark_list, rest, @benchmark_list_switches)

      ["benchmark", "run" | rest] ->
        parse_with_switches(:benchmark_run, rest, @benchmark_run_switches)

      ["benchmark", "show", id] ->
        {:ok, %{command: :benchmark_show, options: %{}, args: [id]}}

      ["benchmark", "import", run_id, subject, file_path] ->
        {:ok, %{command: :benchmark_import, options: %{}, args: [run_id, subject, file_path]}}

      ["benchmark", "export", run_id | rest] ->
        parse_benchmark_export(run_id, rest)

      ["service-account", "create" | rest] ->
        parse_with_switches(:service_account_create, rest, @service_account_create_switches)

      ["service-account", "list" | rest] ->
        parse_with_switches(:service_account_list, rest, @service_account_list_switches)

      ["service-account", "revoke", id] ->
        {:ok, %{command: :service_account_revoke, options: %{}, args: [id]}}

      ["service-account", "rotate", id] ->
        {:ok, %{command: :service_account_rotate, options: %{}, args: [id]}}

      ["policy-set", "create" | rest] ->
        parse_with_switches(:policy_set_create, rest, @policy_set_create_switches)

      ["policy-set", "list" | rest] ->
        parse_with_switches(:policy_set_list, rest, @policy_set_list_switches)

      ["policy-set", "apply", workspace_id, policy_set_id | rest] ->
        parse_policy_set_apply(workspace_id, policy_set_id, rest)

      ["webhook", "create" | rest] ->
        parse_with_switches(:webhook_create, rest, @webhook_create_switches)

      ["webhook", "list" | rest] ->
        parse_with_switches(:webhook_list, rest, @webhook_list_switches)

      ["webhook", "replay", id] ->
        {:ok, %{command: :webhook_replay, options: %{}, args: [id]}}

      ["graph", "show", session_id] ->
        {:ok, %{command: :graph_show, options: %{}, args: [session_id]}}

      ["execute", session_id] ->
        {:ok, %{command: :execute_session, options: %{}, args: [session_id]}}

      ["worker", "start" | rest] ->
        parse_with_switches(:worker_start, rest, @worker_start_switches)

      ["provider", "list" | rest] ->
        parse_with_switches(:provider_list, rest, @provider_list_switches)

      ["provider", "show" | rest] ->
        parse_with_switches(:provider_show, rest, @provider_show_switches)

      ["provider", "doctor" | rest] ->
        parse_with_switches(:provider_doctor, rest, @provider_doctor_switches)

      ["provider", "default", source | rest] ->
        parse_provider_default(source, rest)

      ["provider", "set-key", provider | rest] ->
        parse_provider_set_key(provider, rest)

      ["provider", "set-base-url", provider | rest] ->
        parse_provider_set_base_url(provider, rest)

      ["provider", "set-model", provider | rest] ->
        parse_provider_set_model(provider, rest)

      ["provider", "set-fallback-chain" | rest] ->
        parse_provider_set_fallback_chain(rest)

      ["bootstrap" | rest] ->
        parse_with_switches(:bootstrap, rest, @bootstrap_switches)

      ["mcp" | rest] ->
        parse_with_switches(:mcp, rest, @mcp_switches)

      ["watch" | rest] ->
        parse_with_switches(:watch, rest, @watch_switches)

      ["deploy", "analyze" | rest] ->
        parse_with_switches(:deploy_analyze, rest, @deploy_analyze_switches)

      ["deploy", "cost" | rest] ->
        parse_with_switches(:deploy_cost, rest, @deploy_cost_switches)

      ["deploy", "dns", stack] ->
        {:ok, %{command: :deploy_dns, options: %{stack: stack}, args: []}}

      ["deploy", "migration", stack] ->
        {:ok, %{command: :deploy_migration, options: %{stack: stack}, args: []}}

      ["deploy", "scaling", stack] ->
        {:ok, %{command: :deploy_scaling, options: %{stack: stack}, args: []}}

      ["cost", "optimize" | rest] ->
        parse_with_switches(:cost_optimize, rest, @cost_optimize_switches)

      ["cost", "compare" | rest] ->
        parse_with_switches(:cost_compare, rest, @cost_compare_switches)

      ["precommit-check" | rest] ->
        parse_with_switches(:precommit_check, rest, @precommit_check_switches)

      ["precommit-install" | rest] ->
        parse_with_switches(:precommit_install, rest, @precommit_check_switches)

      ["precommit-uninstall" | rest] ->
        parse_with_switches(:precommit_uninstall, rest, @precommit_check_switches)

      ["progress" | rest] ->
        parse_with_switches(:progress, rest, @progress_switches)

      ["circuit-breaker", "status" | rest] ->
        parse_with_switches(:circuit_breaker_status, rest, @circuit_breaker_switches)

      ["circuit-breaker", "trip", agent_id] ->
        {:ok, %{command: :circuit_breaker_trip, options: %{agent_id: agent_id}, args: []}}

      ["circuit-breaker", "reset", agent_id] ->
        {:ok, %{command: :circuit_breaker_reset, options: %{agent_id: agent_id}, args: []}}

      ["agents", "monitor" | rest] ->
        parse_with_switches(:agents_monitor, rest, @circuit_breaker_switches)

      ["outcome", "record", session_id, outcome] ->
        {:ok, %{command: :outcome_record, options: %{}, args: [session_id, outcome]}}

      ["outcome", "score", agent_id] ->
        {:ok, %{command: :outcome_score, options: %{}, args: [agent_id]}}

      ["outcome", "leaderboard"] ->
        {:ok, %{command: :outcome_leaderboard, options: %{}, args: []}}

      ["help" | rest] ->
        {:ok, %{command: :help, options: %{}, args: rest}}

      ["version"] ->
        {:ok, %{command: :version, options: %{}, args: []}}

      ["update" | rest] ->
        parse_with_switches(:update, rest, @update_switches)

      ["upgrade" | rest] ->
        parse_with_switches(:update, rest, @update_switches)

      _ ->
        {:error, Help.unknown_command_text(argv)}
    end
  end

  def app_required?(%{command: command}) when command in [:help, :version], do: false
  def app_required?(_parsed), do: true

  def server_mode?(%{command: :serve}), do: true
  def server_mode?(_parsed), do: false

  def execute(parsed, opts \\ []) do
    printer = Keyword.get(opts, :printer, &IO.puts/1)
    error_printer = Keyword.get(opts, :error_printer, fn line -> IO.puts(:stderr, line) end)

    project_root =
      opts
      |> Keyword.get(:project_root, File.cwd!())
      |> ProjectRoot.resolve()

    case run_command(parsed, project_root) do
      {:ok, lines} ->
        lines = maybe_wrap_success_envelope(parsed, lines)
        Enum.each(List.wrap(lines), printer)
        0

      :ok ->
        0

      {:error, message} ->
        error_printer.(message)
        1
    end
  end

  # Commands whose JSON output is machine-to-machine data (export/import round-trips)
  # and should NOT be wrapped in the success envelope.
  @skip_envelope_commands ~w(obs_export obs_import audit_export)a

  defp maybe_wrap_success_envelope(parsed, lines) do
    options = Map.get(parsed, :options, %{})
    json? = options[:json] == true or options[:format] == "json"
    skip? = parsed.command in @skip_envelope_commands

    if json? and not skip? and is_list(lines) and length(lines) == 1 do
      [line] = lines

      if is_binary(line) and String.starts_with?(line, "{") do
        case Jason.decode(line) do
          {:ok, %{"status" => status, "data" => _}} when status in ["ok", "error"] ->
            lines

          {:ok, payload} ->
            command_path = catalog_path_for_command(parsed.command)
            [ControlKeel.CLI.Output.success_json(command_path, payload, version: version())]

          {:error, _} ->
            lines
        end
      else
        lines
      end
    else
      lines
    end
  end

  defp catalog_path_for_command(command) when is_atom(command) do
    case Catalog.for_command(command) do
      nil -> command |> Atom.to_string() |> String.replace("_", " ")
      entry -> entry.path
    end
  end

  def version do
    Application.spec(:controlkeel, :vsn)
    |> Kernel.||("0.1.0")
    |> to_string()
  end

  def usage_text, do: Help.usage_text()

  defp format_default_branch(nil), do: ""
  defp format_default_branch(""), do: ""
  defp format_default_branch(branch), do: " (default branch: #{branch})"

  defp format_installation(nil), do: ""
  defp format_installation(""), do: ""
  defp format_installation(id), do: " (installation #{id})"

  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, _key, ""), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)

  defp response_summary(%{status: status, body: body}) when is_map(body) do
    "#{status} workspace=#{Map.get(body, "workspace_id") || Map.get(body, :workspace_id) || "?"}"
  end

  defp response_summary(%{status: status}), do: "#{status}"

  defp enroll_remote(identity, base_url, opts) do
    alias ControlKeel.Cloud.Enrollment

    register_url = String.trim_trailing(base_url, "/") <> "/cloud/v1/workspaces/register"

    with {:ok, envelope} <- Enrollment.build(identity, opts),
         {:ok, response} <- post_enrollment(register_url, envelope) do
      {:ok,
       [
         "Enrolled with: #{base_url}",
         "Server response: #{response_summary(response)}"
       ]}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp post_enrollment(url, envelope) do
    http_module = Application.get_env(:controlkeel, :cloud_enrollment_http_module, Req)

    case http_module.post(url, json: envelope, receive_timeout: 10_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, %{status: status, body: body}}

      {:ok, %{status: status, body: body}} ->
        {:error, "server returned #{status}: #{inspect(body)}"}

      {:error, %{__exception__: true} = error} ->
        {:error, Exception.message(error)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def run_command(%{command: :serve}, _project_root), do: :ok

  def run_command(%{command: :capabilities, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      payload = ControlKeel.CLI.Capabilities.payload()

      case format do
        "json" -> {:ok, [Jason.encode!(payload)]}
        _ -> {:ok, ControlKeel.CLI.Capabilities.lines(payload)}
      end
    end
  end

  def run_command(%{command: :doctor, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      payload = ControlKeel.CLI.Doctor.payload(root, version())

      case format do
        "json" -> {:ok, [Jason.encode!(payload)]}
        _ -> {:ok, ControlKeel.CLI.Doctor.lines(payload)}
      end
    end
  end

  def run_command(%{command: :help, args: args}, _project_root), do: {:ok, [Help.render(args)]}
  def run_command(%{command: :version}, _project_root), do: {:ok, ["ControlKeel #{version()}"]}

  def run_command(%{command: :update, options: options}, project_root) do
    project_root = options[:project_root] || project_root

    {:ok, payload} =
      Updater.apply(project_root,
        apply: options[:apply] == true,
        sync_attached: options[:sync_attached] == true
      )

    case effective_cli_format(options) do
      {:ok, "json"} -> {:ok, [Jason.encode!(payload)]}
      {:ok, _} -> {:ok, Updater.render(payload)}
      {:error, reason} -> {:error, format_cli_error(reason)}
    end
  end

  def run_command(%{command: :init, options: options}, project_root) do
    project_root = resolve_project_root(options, project_root)
    attrs = Enum.into(options, %{}, fn {key, value} -> {Atom.to_string(key), value} end)
    no_attach = Keyword.get(options, :no_attach, false)

    case LocalProject.init(attrs, project_root) do
      {:ok, binding, :created} ->
        base_lines = [
          "Initialized ControlKeel for #{binding["project_root"]}",
          "Project binding: #{ProjectBinding.path(project_root)}",
          "MCP wrapper: #{ProjectBinding.mcp_wrapper_path(project_root)}"
        ]

        attach_lines =
          if no_attach do
            ["To attach to Claude Code: controlkeel attach claude-code"]
          else
            case auto_attach_claude_code(project_root) do
              {:ok, _result} ->
                [
                  "Attached ControlKeel to Claude Code.",
                  "Verified with `claude mcp get controlkeel`."
                ]

              {:skip, reason} ->
                ["To attach to Claude Code: controlkeel attach claude-code  (#{reason})"]

              {:error, _reason} ->
                ["To attach to Claude Code: controlkeel attach claude-code"]
            end
          end

        {:ok, base_lines ++ attach_lines}

      {:ok, binding, :existing} ->
        {:ok,
         [
           "ControlKeel is already initialized for session ##{binding["session_id"]}.",
           "Project binding: #{ProjectBinding.path(project_root)}",
           "MCP wrapper: #{ProjectBinding.mcp_wrapper_path(project_root)}"
         ]}

      {:error, reason} ->
        {:error, "Failed to initialize ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :setup, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    overrides = %{"agent" => options[:agent] || "claude"}

    case ensure_local_project(root, overrides) do
      {:ok, _binding, session, mode} ->
        snapshot = SetupAdvisor.snapshot(root)

        {:ok,
         [
           "ControlKeel setup",
           "Project root: #{snapshot["project_root"]}",
           "Session: #{session.title} (##{session.id})",
           "Binding mode: #{mode}",
           SetupAdvisor.detected_hosts_line(snapshot),
           SetupAdvisor.attached_agents_line(snapshot),
           "Provider source: #{snapshot["provider_status"]["selected_source"]}.",
           "Provider: #{snapshot["provider_status"]["selected_provider"]}.",
           "Core loop: #{SetupAdvisor.core_loop()}",
           "Recommended next steps:"
         ] ++
           Enum.map(SetupAdvisor.recommended_attach_lines(snapshot), &"  - #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  - ")}

      {:error, reason} ->
        {:error, "Failed to set up ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["claude-code"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "claude-code"}),
         {:ok, _scope} <- validate_attach_scope("claude-code", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached_agent} <-
           ClaudeCLI.attach_local(
             root,
             command_spec.command,
             command_spec.args
           ),
         updated_binding <-
           ProjectBinding.update_attached_agent(binding, "claude_code", attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(
             updated_binding,
             root,
             mode: binding_write_mode(binding)
           ) do
      emit_attach_succeeded(binding, root, attached_agent)

      {:ok,
       [
         "Attached ControlKeel to Claude Code.",
         "Verified with `claude mcp get controlkeel`."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("claude-code", root, options) ++
         attach_guidance_lines("claude-code")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["cursor"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "cursor"}),
         {:ok, _scope} <- validate_attach_scope("cursor", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached} <- attach_to_cursor(command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "cursor", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Cursor.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Cursor to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("cursor", root, options) ++ attach_guidance_lines("cursor")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Cursor: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["windsurf"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "windsurf"}),
         {:ok, _scope} <- validate_attach_scope("windsurf", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached} <- attach_to_windsurf(command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "windsurf", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Windsurf.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Windsurf to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("windsurf", root, options) ++
         attach_guidance_lines("windsurf")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Windsurf: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["codex-cli", "codex-app-server", "t3code"] do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         config_path <- CodexConfig.path_for_scope(root, scope),
         {:ok, _} <- CodexConfig.write(config_path, command_spec),
         {:ok, install_result} <- maybe_install_codex_native(root, scope, options),
         attached <-
           %{
             "server_name" => "controlkeel",
             "ide" => agent,
             "config_path" => config_path,
             "scope" => scope,
             "target" => "codex",
             "destination" => install_result && install_result[:destination],
             "compat_destination" => install_result && install_result[:compat_destination],
             "agents_destination" => install_result && install_result[:agent_destination],
             "commands_destination" => install_result && install_result[:commands_destination],
             "config_destination" => config_path,
             "controlkeel_version" => to_string(Application.spec(:controlkeel, :vsn) || "0.2.0"),
             "attached_at" =>
               DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
           },
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to #{display_attach_agent(agent)}.",
         "MCP server written to #{config_path}.",
         "Restart #{display_attach_agent(agent)} to activate."
       ] ++
         bootstrap_lines(root) ++
         codex_attach_install_lines(install_result) ++ attach_guidance_lines(agent)}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["kiro", "kilo", "amp", "augment", "opencode", "gemini-cli", "cline"] do
    config_path_fn = %{
      "kiro" => &kiro_mcp_config_path/0,
      "kilo" => &kilo_config_path/0,
      "amp" => &amp_mcp_config_path/0,
      "augment" => &augment_mcp_config_path/0,
      "opencode" => &opencode_mcp_config_path/0,
      "gemini-cli" => &gemini_cli_config_path/0,
      "cline" => &cline_mcp_config_path/0
    }

    display_name = %{
      "kiro" => "Kiro",
      "kilo" => "Kilo Code",
      "amp" => "Amp",
      "augment" => "Augment / Auggie CLI",
      "opencode" => "OpenCode",
      "gemini-cli" => "Gemini CLI",
      "cline" => "Cline"
    }

    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, _scope} <- validate_attach_scope(agent, options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         config_path <- config_path_fn[agent].(),
         {:ok, attached} <- write_ide_mcp_config(config_path, "controlkeel", command_spec, agent),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to #{display_name[agent]}.",
         "MCP server written to #{attached["config_path"]}.",
         if(agent == "augment",
           do:
             "Restart Auggie or use `auggie --mcp-config #{attached["config_path"]}` to activate.",
           else: "Restart #{display_name[agent]} to activate."
         )
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines(agent, root, options) ++
         attach_guidance_lines(agent)}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to #{display_name[agent]}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["goose"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "goose"}),
         {:ok, _scope} <- validate_attach_scope("goose", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached} <- attach_to_goose(command_spec, root),
         updated <- ProjectBinding.update_attached_agent(binding, "goose", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Goose.",
         "Goose extension written to #{attached["config_path"]}.",
         "Restart Goose to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("goose", root, options) ++
         attach_guidance_lines("goose")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Goose: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["continue"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "continue"}),
         {:ok, _scope} <- validate_attach_scope("continue", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached} <-
           write_continue_mcp_config(continue_config_path(), "controlkeel", command_spec),
         updated <- ProjectBinding.update_attached_agent(binding, "continue", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Continue.",
         "MCP server written to #{attached["config_path"]}.",
         "Restart Continue to activate."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("continue", root, options) ++
         attach_guidance_lines("continue")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Continue: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: ["aider"], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => "aider"}),
         {:ok, _scope} <- validate_attach_scope("aider", options),
         command_spec <- ProjectBinding.mcp_command_spec(root),
         {:ok, attached} <- attach_to_aider(command_spec, root),
         updated <- ProjectBinding.update_attached_agent(binding, "aider", attached),
         {:ok, _} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       [
         "Attached ControlKeel to Aider.",
         "MCP config written to #{attached["config_path"]}."
       ] ++
         bootstrap_lines(root) ++
         native_attach_lines("aider", root, options) ++
         attach_guidance_lines("aider")}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to attach ControlKeel to Aider: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in [
             "roo-code",
             "hermes-agent",
             "openclaw",
             "droid",
             "forge",
             "pi",
             "letta-code",
             "devin-terminal",
             "warp",
             "multica",
             "antigravity-cli",
             "antigravity-ide"
           ] do
    root = options[:project_root] || project_root

    target =
      %{
        "roo-code" => "roo-native",
        "hermes-agent" => "hermes-native",
        "openclaw" => "openclaw-native",
        "droid" => "droid-bundle",
        "forge" => "forge-acp",
        "pi" => "pi-native",
        "letta-code" => "letta-code-native",
        "devin-terminal" => "devin-terminal-native",
        "warp" => "warp-native",
        "multica" => "multica-native",
        "antigravity-cli" => "antigravity-cli-native",
        "antigravity-ide" => "antigravity-cli-native"
      }[agent]

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         {:ok, result} <- attach_bundle_target(target, root, scope, options),
         attached_agent <- bundled_attached_agent(agent, target, scope, result),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      {:ok,
       bundle_attach_lines(agent, result) ++
         bootstrap_lines(root) ++
         attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :attach, args: [agent], options: options}, project_root)
      when agent in ["vscode", "copilot"] do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <-
           ensure_attach_project(root, %{"agent" => agent}),
         {:ok, scope} <- validate_attach_scope(agent, options),
         {:ok, install_result} <- Skills.install("github-repo", root, scope: scope),
         attached_agent <- github_repo_attached_agent(agent, scope, install_result),
         updated <- ProjectBinding.update_attached_agent(binding, agent, attached_agent),
         {:ok, _binding} <-
           ProjectBinding.write_effective(updated, root, mode: binding_write_mode(binding)) do
      lines =
        case install_result do
          %{destination: destination} ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Installed project bundle at #{destination}.",
              "Repository MCP config written under .github and .vscode."
            ] ++ bootstrap_lines(root)

          %ControlKeel.Skills.SkillExportPlan{} = plan ->
            [
              "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
              "Output: #{plan.output_dir}"
            ] ++ bootstrap_lines(root)
        end

      {:ok, lines ++ attach_guidance_lines(agent)}
    else
      {:error, reason} ->
        {:error,
         "Failed to attach ControlKeel to #{display_attach_agent(agent)}: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["open-swe"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("open-swe-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Open SWE runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Open SWE runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["devin"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("devin-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Devin runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Devin runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["executor"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("executor-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Executor runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Executor runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: ["warp-oz"], options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("warp-oz-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Warp Oz runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Warp Oz runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :runtime_export, args: ["cloudflare-workers"], options: options},
        project_root
      ) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("cloudflare-workers-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Cloudflare Workers runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Cloudflare Workers runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :runtime_export, args: ["virtual-bash"], options: options},
        project_root
      ) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("virtual-bash-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared virtual bash runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export virtual bash runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :runtime_export, args: ["multica-cloud"], options: options},
        project_root
      ) do
    root = resolve_project_root(options, project_root)
    snapshot = SetupAdvisor.snapshot(root)

    case Skills.export("multica-cloud-runtime", root, scope: "export") do
      {:ok, plan} ->
        {:ok,
         [
           "Prepared Multica Cloud runtime export.",
           "Project root: #{snapshot["project_root"]}",
           SetupAdvisor.detected_hosts_line(snapshot),
           "Output: #{plan.output_dir}",
           "Core loop: #{SetupAdvisor.core_loop()}"
         ] ++
           Enum.map(plan.instructions, &"  #{&1}") ++
           maybe_line(SetupAdvisor.service_account_hint(snapshot), "  ")}

      {:error, reason} ->
        {:error, "Failed to export Multica Cloud runtime bundle: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :runtime_export, args: [runtime_id]}, _project_root) do
    {:error, "Unknown runtime export target: #{runtime_id}"}
  end

  def run_command(%{command: :review_diff, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, base_ref} <- required_option(options, :base, "--base"),
         {:ok, head_ref} <- required_option(options, :head, "--head"),
         {:ok, review} <-
           Governance.review_diff(
             base_ref,
             head_ref,
             governance_opts(options, root)
           ) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_pr, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, review} <- review_pr_input(options, root) do
      {:ok, review_lines(review, "merge")}
    end
  end

  def run_command(%{command: :review_socket, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, report} <- socket_report_input(options),
         {:ok, dependency_review} <- GovernanceSocket.dependency_review(report),
         {:ok, review} <-
           Governance.review_patch(
             "",
             governance_opts(options, root)
             |> Keyword.put(:dependency_review, dependency_review)
             |> Keyword.put(:source, "socket_review")
             |> Keyword.put(:phase, "dependency_review")
           ) do
      {:ok, review_lines(review, "dependency")}
    end
  end

  def run_command(%{command: :review_plan_submit, options: options}, project_root) do
    project_root = resolve_project_root(options, project_root)

    with {:ok, submission_body} <- review_submission_input(options),
         {:ok, attrs} <- review_submission_attrs(options, submission_body, project_root),
         {:ok, review} <- Mission.submit_review(attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "submitted",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Submitted plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}",
           "Execution gate: task remains blocked until the plan review is approved."
         ]}
      end
    else
      {:error, reason} ->
        cli_error("Failed to submit plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_open, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review_open} <-
           ReviewBridge.open_review(review_id, auto_open: ReviewBridge.auto_open_reviews?()) do
      review = review_open.review

      payload =
        review_cli_payload(review, %{
          "message" => "open",
          "browser_url" => review_open.url,
          "browser_embed" => review_open.browser_embed,
          "open_target" => review_open.open_target,
          "remote" => review_open.remote,
          "opened" => review_open.opened,
          "open_error" => review_open.open_error,
          "server_serving" => review_open.server_serving,
          "server_status" => review_open.server_status,
          "server_error" => review_open.server_error
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Review ##{review.id}: #{review.title}",
           "Status: #{review.status}",
           "Type: #{review.review_type}",
           "Browser URL: #{review_open.url}",
           "Browser embed: #{review_open.browser_embed}"
         ] ++
           maybe_cli_line("Open target", review_open.open_target) ++
           maybe_cli_line("Review server serving", to_string(review_open.server_serving)) ++
           maybe_cli_line("Review server error", review_open.server_error) ++
           maybe_cli_line("Opened browser", to_string(review_open.opened)) ++
           maybe_cli_line("Open error", review_open.open_error) ++
           manual_approval_lines(review, review_open)}
      end
    else
      {:error, :not_found} ->
        cli_error("Review not found", :not_found, options)

      {:error, reason} ->
        cli_error("Failed to open plan review", reason, options)
    end
  end

  def run_command(%{command: :review_plan_wait, options: options}, _project_root) do
    with {:ok, review_id} <- required_integer_option(options, :id, "--id"),
         {:ok, review} <-
           ReviewBridge.wait_for_review(review_id,
             timeout_ms: (options[:timeout] || 120) * 1000,
             interval_ms: options[:interval_ms] || 1000
           ) do
      payload =
        review_cli_payload(review, %{
          "message" => "wait",
          "browser_url" => review_url(review.id)
        })

      case review.status do
        "approved" ->
          if options[:json] do
            {:ok, [Jason.encode!(payload)]}
          else
            {:ok,
             [
               "Plan review ##{review.id} approved.",
               "Status: #{review.status}",
               "Browser URL: #{review_url(review.id)}"
             ] ++ review_feedback_lines(review)}
          end

        "denied" ->
          cli_error(
            "Plan review ##{review.id} was denied",
            {:review_denied, review},
            options,
            payload
          )

        other ->
          cli_error(
            "Plan review ##{review.id} is still #{other}",
            {:review_pending, %{review_id: review.id, review_status: other}},
            options,
            payload
          )
      end
    else
      {:error, {:timeout, review}} ->
        payload =
          review_cli_payload(review, %{
            "message" => "timeout",
            "timed_out" => true,
            "status" => review.status,
            "browser_url" => review_url(review.id)
          })

        if review.status in ["pending", "superseded"] do
          if options[:json] do
            {:ok, [Jason.encode!(payload)]}
          else
            {:ok,
             [
               "Timed out waiting for plan review ##{review.id}.",
               "Status: #{review.status}",
               "Browser URL: #{review_url(review.id)}",
               "Review is still open; keep waiting or respond in browser."
             ]}
          end
        else
          cli_error(
            "Timed out waiting for plan review ##{review.id}",
            {:timeout, review},
            options,
            payload
          )
        end

      {:error, reason} ->
        cli_error("Failed while waiting for plan review", reason, options)
    end
  end

  def run_command(
        %{command: :review_plan_respond, args: [review_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(review_id),
         {:ok, decision} <- required_option(options, :decision, "--decision"),
         attrs <- review_response_attrs(options, decision),
         {:ok, review} <- Mission.respond_review(parsed_id, attrs) do
      payload =
        review_cli_payload(review, %{
          "message" => "responded",
          "browser_url" => review_url(review.id)
        })

      if options[:json] do
        {:ok, [Jason.encode!(payload)]}
      else
        {:ok,
         [
           "Updated plan review ##{review.id}.",
           "Status: #{review.status}",
           "Browser URL: #{review_url(review.id)}"
         ]}
      end
    else
      {:error, :invalid_id} ->
        cli_error("Review id must be an integer", :invalid_id, options)

      {:error, reason} ->
        cli_error("Failed to respond to plan review", reason, options)
    end
  end

  def run_command(%{command: :release_ready, options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, session_id} <- release_ready_session_id(options, root),
         {:ok, readiness} <-
           Governance.release_readiness(
             release_ready_opts(options, root)
             |> Map.put(:session_id, session_id)
           ) do
      {:ok, release_ready_lines(readiness)}
    end
  end

  def run_command(%{command: :govern_install_github, options: options}, project_root) do
    root = options[:project_root] || project_root

    case Governance.install_github_scaffolding(root) do
      {:ok, result} ->
        {:ok,
         [
           "Installed ControlKeel GitHub governance scaffolding.",
           "Project root: #{result["project_root"]}"
         ] ++ Enum.map(result["files"], &"  #{&1}")}

      {:error, message} ->
        {:error, message}
    end
  end

  def run_command(%{command: :govern_bind_github, options: options}, _project_root) do
    alias ControlKeel.Mission

    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, owner} <- require_string_option(options[:owner], "owner"),
         {:ok, repo} <- require_string_option(options[:repo], "repo") do
      opts =
        []
        |> maybe_put_kw(:default_branch, options[:default_branch])
        |> maybe_put_kw(:installation_id, options[:installation_id])

      case Mission.bind_github_repo(workspace_id, owner, repo, opts) do
        {:ok, binding} ->
          {:ok,
           [
             "Bound GitHub repository to workspace #{workspace_id}.",
             "Repo: #{binding.owner}/#{binding.repo}",
             "URL:  https://github.com/#{binding.owner}/#{binding.repo}",
             "Default branch: #{binding.default_branch || "(unset)"}",
             "Installation: #{binding.installation_id || "(unauthenticated)"}"
           ]}

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, "Failed to bind repo: #{format_changeset_errors(cs)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      {:error, msg} when is_binary(msg) -> {:error, msg}
    end
  end

  def run_command(%{command: :govern_unbind_github, options: options}, _project_root) do
    alias ControlKeel.Mission

    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, owner} <- require_string_option(options[:owner], "owner"),
         {:ok, repo} <- require_string_option(options[:repo], "repo") do
      case Mission.unbind_github_repo(workspace_id, owner, repo) do
        {:ok, _} ->
          {:ok, ["Unbound #{owner}/#{repo} from workspace #{workspace_id}."]}

        {:error, :not_found} ->
          {:error, "No binding found for #{owner}/#{repo} on workspace #{workspace_id}."}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      {:error, msg} when is_binary(msg) -> {:error, msg}
    end
  end

  def run_command(%{command: :govern_list_github, options: options}, _project_root) do
    alias ControlKeel.Mission

    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      case Mission.list_github_repos(workspace_id) do
        [] ->
          {:ok, ["No GitHub repos bound to workspace #{workspace_id}."]}

        bindings ->
          rows =
            Enum.map(bindings, fn b ->
              "  #{b.owner}/#{b.repo}#{format_default_branch(b.default_branch)}#{format_installation(b.installation_id)}"
            end)

          {:ok, ["GitHub repos bound to workspace #{workspace_id}:" | rows]}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :plugin_export, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, target} <- plugin_target(plugin),
         {:ok, plan} <- Skills.export(target, root, scope: "export") do
      {:ok,
       [
         "Exported #{plugin} plugin bundle.",
         "Target: #{plan.target}",
         "Output: #{plan.output_dir}"
       ] ++ Enum.map(plan.instructions, &"  #{&1}")}
    else
      {:error, reason} ->
        {:error, "Failed to export plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :plugin_install, args: [plugin], options: options}, project_root) do
    root = options[:project_root] || project_root
    scope = options[:scope] || "project"
    mode = options[:mode] || "local"

    with {:ok, target} <- plugin_target(plugin) do
      case Skills.install(target, root, scope: scope) do
        {:ok, %{destination: destination} = result} ->
          {:ok,
           [
             "Installed #{plugin} plugin bundle.",
             "Target: #{target}",
             "Scope: #{scope}",
             "Destination: #{destination}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++
             maybe_cli_line("Marketplace", Map.get(result, :marketplace_destination))}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:ok,
           [
             "Prepared #{plugin} plugin bundle.",
             "Target: #{plan.target}",
             "Scope: #{scope}",
             "Output: #{plan.output_dir}",
             "MCP mode: #{mode} (use #{plugin_mcp_hint(mode)})"
           ] ++ Enum.map(plan.instructions, &"  #{&1}")}

        {:error, reason} ->
          {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Failed to install plugin bundle: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :cloud_doctor, options: _options}, _project_root) do
    report = ControlKeel.Cloud.Doctor.report()
    lines = ControlKeel.Cloud.Doctor.format(report)

    if report.ok do
      {:ok, lines}
    else
      {:error, Enum.join(lines, "\n")}
    end
  end

  def run_command(%{command: :cloud_connect, options: options}, _project_root) do
    force? = Map.get(options, :rotate, false)
    enroll_url = Map.get(options, :enroll)
    name = Map.get(options, :name)
    invite = Map.get(options, :invite)

    case ControlKeel.Cloud.WorkspaceIdentity.ensure(force: force?) do
      {:ok, identity, outcome} ->
        action =
          case outcome do
            :existing -> "Already connected"
            :created -> "Workspace identity created"
            :rotated -> "Workspace identity rotated"
          end

        base = [
          action,
          "Workspace ID: #{identity.workspace_id}",
          "Algorithm: #{identity.algorithm}",
          "Fingerprint: #{ControlKeel.Cloud.WorkspaceIdentity.short_fingerprint(identity)}...",
          "Created at: #{DateTime.to_iso8601(identity.created_at)}",
          "Identity path: #{identity.path}"
        ]

        case enroll_url do
          nil ->
            {:ok,
             base ++
               [
                 "Note: this is a local identity primitive. Pass --enroll <url> to register with a control plane."
               ]}

          url when is_binary(url) and url != "" ->
            case enroll_remote(identity, url, name: name, invite_token: invite) do
              {:ok, summary_lines} -> {:ok, base ++ summary_lines}
              {:error, reason} -> {:error, "Enrolment failed: #{reason}"}
            end
        end

      {:error, reason} ->
        {:error, "Failed to generate workspace identity: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :cloud_sync_push, options: _options}, _project_root) do
    case ControlKeel.Cloud.SyncEngine.force_sync() do
      {:ok, %{push: %{pushed: n}}} ->
        {:ok, ["Pushed #{n} record(s) to cloud."]}

      {:error, :not_configured} ->
        {:error, "Cloud sync endpoint not configured. Set cloud_sync_endpoint first."}

      {:error, :not_enrolled} ->
        {:error, "Cloud sync not configured. Run `controlkeel cloud connect` first."}

      {:error, :already_syncing} ->
        {:error, "Sync already in progress. Try again in a moment."}

      {:error, reason} ->
        {:error, "Cloud push failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :cloud_sync_pull, options: _options}, _project_root) do
    case ControlKeel.Cloud.SyncEngine.force_sync() do
      {:ok, %{pull: pull_result}} ->
        applied = Map.get(pull_result, :inserted, 0) + Map.get(pull_result, :updated, 0)
        {:ok, ["Pulled and applied #{applied} record(s) from cloud."]}

      {:error, :not_configured} ->
        {:error, "Cloud sync endpoint not configured. Set cloud_sync_endpoint first."}

      {:error, :not_enrolled} ->
        {:error, "Cloud sync not configured. Run `controlkeel cloud connect` first."}

      {:error, :already_syncing} ->
        {:error, "Sync already in progress. Try again in a moment."}

      {:error, reason} ->
        {:error, "Cloud pull failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :cloud_sync_migrate, options: _options}, _project_root) do
    {:ok,
     [
       "Cloud sync schema migrations (external_id, synced_at, lock_version) are managed by Ecto.",
       "Run `mix ecto.migrate` to apply any pending migrations.",
       "Run `mix ecto.migrations` to see current status."
     ]}
  end

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

  def run_command(%{command: :selfhost_pack, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    pack_opts = Enum.reject([output: options[:output]], fn {_, v} -> is_nil(v) end)

    case ControlKeel.SelfHost.pack(root, pack_opts) do
      {:ok, %{path: path, sha256: sha256}} ->
        {:ok,
         [
           "Air-gapped bundle written: #{path}",
           "SHA256: #{sha256}",
           "",
           "Ship this file to your air-gapped host. See INSTALL.md for boot instructions."
         ]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run_command(%{command: :selfhost_verify, options: _options}, _project_root) do
    result = ControlKeel.SelfHost.verify_environment()

    header = [
      "ControlKeel self-host verify",
      "Ready: #{result.ready?}",
      "Runtime mode: #{result.repo.mode}",
      "Cloud repo enabled: #{result.repo.cloud_repo_enabled?}",
      "Repo reachable: #{result.repo.repo_reachable?}#{format_repo_error(result.repo.error)}",
      "",
      "Required environment:"
    ]

    required_rows =
      Enum.map(result.required_env, fn check ->
        badge = if check.present?, do: "ok  ", else: "MISS"
        "  [#{badge}] #{check.name}#{format_value_hint(check.value_hint)}"
      end)

    recommended_rows =
      ["", "Recommended environment:"] ++
        Enum.map(result.recommended_env, fn check ->
          badge = if check.present?, do: "ok  ", else: "-   "
          "  [#{badge}] #{check.name}#{format_value_hint(check.value_hint)}"
        end)

    lines = header ++ required_rows ++ recommended_rows

    if result.ready? do
      {:ok, lines}
    else
      {:error, Enum.join(lines, "\n")}
    end
  end

  def run_command(%{command: :selfhost_manifest, options: _options}, _project_root) do
    paths = ControlKeel.SelfHost.bundle_manifest()
    {:ok, ["Air-gapped bundle manifest:"] ++ Enum.map(paths, &"  #{&1}")}
  end

  def run_command(%{command: :selfhost_install_guide, options: _options}, _project_root) do
    {:ok, [ControlKeel.SelfHost.install_guide()]}
  end

  def run_command(%{command: :agents_discover, options: options, args: [path]}, _project_root) do
    alias ControlKeel.Cloud.AgentInventory

    scan_opts =
      case options[:max_depth] do
        n when is_integer(n) -> [max_depth: n]
        _ -> []
      end

    case AgentInventory.scan(path, scan_opts) do
      {:error, :not_found} ->
        {:error, "Path not found: #{path}"}

      {:error, :not_a_directory} ->
        {:error, "Not a directory: #{path}"}

      {:ok, hits} ->
        if Map.get(options, :json, false) do
          summary = AgentInventory.summarize(hits)
          {:ok, [Jason.encode!(%{hits: hits, summary: summary}, pretty: true)]}
        else
          summary = AgentInventory.summarize(hits)

          header = [
            "Agent inventory scan",
            "Root: #{Path.expand(path)}",
            "Total hits: #{summary.total}",
            ""
          ]

          rows =
            if summary.by_host == [] do
              ["No agent host evidence found."]
            else
              ["By host:"] ++
                Enum.map(summary.by_host, fn h ->
                  "  #{h.host}\t(#{h.count}) — #{Enum.join(h.evidence, ", ")}"
                end) ++
                ["", "Hits:"] ++
                Enum.map(hits, fn hit ->
                  "  #{hit.host}\t#{hit.path}\t#{hit.kind}\t#{hit.evidence}"
                end)
            end

          {:ok, header ++ rows}
        end
    end
  end

  def run_command(%{command: :audit_export, options: options}, _project_root) do
    alias ControlKeel.Cloud.AuditExport
    alias ControlKeel.Cloud.ComplianceTemplate

    with {:ok, scope_opts} <- resolve_audit_scope(options),
         {:ok, since_opt} <- parse_optional_datetime(options[:since], "since"),
         {:ok, until_opt} <- parse_optional_datetime(options[:until], "until"),
         build_opts <-
           scope_opts
           |> maybe_append(:since, since_opt)
           |> maybe_append(:until, until_opt),
         {:ok, bundle} <- AuditExport.build(build_opts),
         {:ok, export_payload} <- maybe_render_compliance_template(bundle, options[:template]),
         {:ok, final_payload} <- maybe_sign_audit_export(export_payload, options) do
      json = Jason.encode!(final_payload, pretty: true)

      case options[:out] do
        nil ->
          {:ok, [json]}

        path ->
          case File.write(path, json) do
            :ok ->
              {:ok,
               [
                 "Audit export written",
                 "Path: #{path}",
                 "Scope: #{bundle["scope"]["type"]}/#{bundle["scope"]["id"]}",
                 "Template: #{options[:template] || "raw"}",
                 "Findings: #{length(bundle["findings"])}",
                 "Reviews: #{length(bundle["reviews"])}",
                 "MCP calls: #{length(bundle["mcp_tool_calls"])}"
               ]}

            {:error, reason} ->
              {:error, "Failed to write #{path}: #{inspect(reason)}"}
          end
      end
    else
      {:error, :scope_required} ->
        {:error, "Provide --workspace <slug> or --org <slug>"}

      {:error, :scope_conflict} ->
        {:error, "Pass exactly one of --workspace or --org"}

      {:error, :unknown_workspace} ->
        {:error, "Workspace not found"}

      {:error, :unknown_org} ->
        {:error, "Org not found"}

      {:error, {:invalid_datetime, name}} ->
        {:error, "--#{name} must be an ISO8601 timestamp (e.g. 2026-01-01T00:00:00Z)"}

      {:error, :unsupported_template} ->
        {:error,
         "--template must be one of: " <>
           Enum.join(ComplianceTemplate.supported_templates(), ", ")}

      {:error, :missing_signing_key_env} ->
        {:error, "--sign requires --signing-key-env <ENV>"}

      {:error, {:missing_signing_key, env}} ->
        {:error, "Signing key environment variable is not set: #{env}"}

      {:error, reason} ->
        {:error, "Failed: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :eval_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.EvalRunner

    suites = EvalRunner.list_suites()

    rows =
      if suites == [] do
        ["No eval suites available."]
      else
        ["Eval suites:"] ++
          Enum.map(suites, fn s ->
            "  #{s.slug}\t(#{s.case_count} cases)\t#{s.title}"
          end)
      end

    {:ok, rows}
  end

  def run_command(%{command: :eval_run, options: options}, _project_root) do
    alias ControlKeel.Cloud.EvalRunner

    slug = options[:suite] || "governance-regression"

    case EvalRunner.run(slug) do
      :not_found ->
        {:error, "Unknown eval suite: #{slug}"}

      {:ok, result} ->
        header = [
          "Eval suite: #{result.title} (#{result.slug})",
          "Total: #{result.total}",
          "Passed: #{result.passed}",
          "Failed: #{result.failed}"
        ]

        case_rows =
          Enum.map(result.cases, fn c ->
            badge = if c.status == :pass, do: "PASS", else: "FAIL"

            extras =
              cond do
                c.missing_rule_ids != [] ->
                  " missing=#{Enum.join(c.missing_rule_ids, ",")}"

                c.unexpected_block_rule_ids != [] ->
                  " unexpected_block=#{Enum.join(c.unexpected_block_rule_ids, ",")}"

                true ->
                  ""
              end

            "  [#{badge}] #{c.name} decision=#{c.decision}#{extras}"
          end)

        lines = header ++ case_rows

        if result.failed == 0 do
          {:ok, lines}
        else
          {:error, Enum.join(lines, "\n")}
        end
    end
  end

  def run_command(
        %{command: :run_cloud_agent, options: options, args: [task_id_str]},
        project_root
      ) do
    alias ControlKeel.Cloud.RuntimeContext
    alias ControlKeel.Mission

    with {:ok, task_id} <- parse_integer_arg(task_id_str, "task-id"),
         {:ok, runtime} <- require_string_option(options[:runtime], "runtime"),
         :ok <- validate_runtime_target(runtime),
         {:ok, budget} <- validate_budget_cents(options[:budget_cents]),
         %{} = task <- Mission.get_task(task_id) do
      session = Mission.get_session(task.session_id)
      workspace_id = session && session.workspace_id

      cond do
        workspace_id == nil ->
          {:error, "Task #{task_id} has no associated workspace"}

        true ->
          root = options[:project_root] || project_root
          git = capture_git_metadata(root, options)

          attrs =
            %{
              workspace_id: workspace_id,
              session_id: session.id,
              task_id: task.id,
              runtime_target: runtime,
              budget_cents_allocated: budget,
              scopes: parse_scopes(options[:scopes]),
              payload: build_cloud_payload(task, options),
              user_id: options[:user_id]
            }
            |> Map.merge(git)

          case RuntimeContext.create_package(attrs) do
            {:ok, package, raw_token} ->
              dispatch? = options[:dispatch] == true

              {final_package, dispatch_lines} =
                if dispatch? do
                  case RuntimeContext.dispatch_package(package, raw_token) do
                    {:ok, dispatched} ->
                      meta = get_in(dispatched.payload, ["dispatch_metadata"]) || %{}

                      {dispatched,
                       [
                         "Dispatched via: #{Map.get(meta, "mode", "(unknown)")}",
                         "Dispatch note: #{Map.get(meta, "note", "")}"
                       ]}

                    {:error, reason} ->
                      {package, ["Dispatch failed: #{inspect(reason)}"]}
                  end
                else
                  {package, []}
                end

              {:ok,
               [
                 "Cloud run package created",
                 "Package: #{final_package.external_id}",
                 "Task: #{task.id} — #{task.title}",
                 "Runtime: #{final_package.runtime_target}",
                 "Budget allocated (cents): #{final_package.budget_cents_allocated}",
                 "Scopes: #{final_package.scopes || "(none)"}",
                 "Repo: #{final_package.repo_url || "(none)"}",
                 "Branch: #{final_package.branch || "(none)"}",
                 "Commit: #{final_package.commit_sha || "(none)"}",
                 "Callback token (deliver out of band): #{raw_token}",
                 "Status: #{final_package.status}"
               ] ++ dispatch_lines}

            {:error, :unauthorized} ->
              {:error,
               "Cloud execution unauthorized: workspace belongs to an org and no valid membership was found. Provide --user-id with an active org member."}

            {:error, :org_suspended} ->
              {:error, "Cloud execution unauthorized: workspace org is suspended."}

            {:error, :not_found} ->
              {:error, "Cloud execution unauthorized: workspace not found."}

            {:error, changeset} ->
              {:error, "Failed to create package: #{format_changeset_errors(changeset)}"}
          end
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      {:error, msg} when is_binary(msg) -> {:error, msg}
      nil -> {:error, "Task not found: #{task_id_str}"}
    end
  end

  def run_command(%{command: :user_create, options: options}, _project_root) do
    alias ControlKeel.Accounts

    with {:ok, email} <- require_string_option(options[:email], "email") do
      attrs = %{email: email, name: options[:name]}

      case Accounts.create_user(attrs) do
        {:ok, user} ->
          {:ok,
           [
             "User created",
             "ID: #{user.id}",
             "Email: #{user.email}",
             "Name: #{user.name || "(none)"}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to create user: #{format_changeset_errors(changeset)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :org_create, options: options}, _project_root) do
    alias ControlKeel.Accounts

    with {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, slug} <- require_string_option(options[:slug], "slug") do
      case Accounts.create_org(%{name: name, slug: slug}) do
        {:ok, org} ->
          {:ok,
           [
             "Org created",
             "ID: #{org.id}",
             "Name: #{org.name}",
             "Slug: #{org.slug}",
             "Status: #{org.status}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to create org: #{format_changeset_errors(changeset)}"}
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
    end
  end

  def run_command(%{command: :org_list, options: _options}, _project_root) do
    alias ControlKeel.Accounts

    orgs = Accounts.list_orgs()

    if orgs == [] do
      {:ok, ["No orgs configured."]}
    else
      header = ["Orgs:"]

      rows =
        Enum.map(orgs, fn o ->
          budget = Accounts.org_budget_cents(o) || "uncapped"
          "  #{o.slug}\t#{o.name}\tbudget=#{budget}\tstatus=#{o.status}"
        end)

      {:ok, header ++ rows}
    end
  end

  def run_command(%{command: :org_budget_set, options: options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        cents =
          cond do
            Map.get(options, :clear, false) -> nil
            is_integer(options[:cents]) -> options[:cents]
            true -> :unset
          end

        case cents do
          :unset ->
            {:error, "Provide either --cents N or --clear"}

          value ->
            case Accounts.set_org_budget_cents(org.id, value) do
              {:ok, _} ->
                {:ok,
                 [
                   "Org budget updated",
                   "Org: #{org.slug}",
                   "Budget: #{value || "uncapped"}"
                 ]}

              {:error, reason} ->
                {:error, "Failed: #{inspect(reason)}"}
            end
        end
    end
  end

  def run_command(%{command: :org_budget_show, options: _options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        status = Accounts.org_budget_status(org.id)
        breakdown = Accounts.org_workspace_breakdown(org.id)

        header = [
          "Org: #{org.slug}",
          "Budget: #{status.budget_cents || "uncapped"}",
          "Spent: #{status.spent_cents}",
          "Remaining: #{status.remaining_cents || "—"}",
          "Workspaces: #{status.workspace_count}",
          "Over cap: #{status.over_cap?}"
        ]

        rows =
          case breakdown do
            [] ->
              []

            ws ->
              ["Workspace breakdown:"] ++
                Enum.map(ws, &"  #{&1.workspace_slug}\t#{&1.spent_cents}")
          end

        {:ok, header ++ rows}
    end
  end

  def run_command(%{command: :org_invite, options: options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    with {:ok, email} <- require_string_option(options[:email], "email"),
         org when not is_nil(org) <- Accounts.get_org_by_slug(slug) do
      user =
        Accounts.get_user_by_email(email) ||
          case Accounts.create_user(%{email: email}) do
            {:ok, u} -> u
            _ -> nil
          end

      cond do
        user == nil ->
          {:error, "Could not find or create user for #{email}"}

        true ->
          role = options[:role] || "member"

          case Accounts.invite_member(user.id, org.id, role: role) do
            {:ok, membership, raw_token} ->
              {:ok,
               [
                 "Invitation created",
                 "Org: #{org.slug}",
                 "User: #{user.email}",
                 "Role: #{membership.role}",
                 "Invitation token (deliver out of band): #{raw_token}"
               ]}

            {:error, changeset} ->
              {:error, "Failed to invite: #{format_changeset_errors(changeset)}"}
          end
      end
    else
      {:error, {:missing_option, opt}} -> {:error, "Missing required option --#{opt}"}
      nil -> {:error, "Org not found: #{slug}"}
    end
  end

  def run_command(%{command: :org_idp_set, options: options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        cond do
          Map.get(options, :clear, false) ->
            case Accounts.set_org_identity_provider(org.id, nil) do
              {:ok, _} ->
                {:ok, ["Identity provider cleared for #{org.slug}"]}

              {:error, reason} ->
                {:error, "Failed: #{inspect(reason)}"}
            end

          true ->
            attrs =
              %{
                "type" => options[:type],
                "issuer" => options[:issuer],
                "client_id" => options[:client_id],
                "entity_id" => options[:entity_id],
                "idp_metadata_url" => options[:idp_metadata_url]
              }
              |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
              |> Map.new()

            case Accounts.set_org_identity_provider(org.id, attrs) do
              {:ok, _} ->
                {:ok,
                 [
                   "Identity provider configured",
                   "Org: #{org.slug}",
                   "Type: #{options[:type]}"
                 ]}

              {:error, :unsupported_provider_type} ->
                {:error, "Provide --type oidc or --type saml"}

              {:error, {:missing_fields, fields}} ->
                {:error,
                 "Missing required field(s) for #{options[:type]}: " <> Enum.join(fields, ", ")}

              {:error, reason} ->
                {:error, "Failed: #{inspect(reason)}"}
            end
        end
    end
  end

  def run_command(%{command: :org_idp_show, options: _options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        case Accounts.get_org_identity_provider(org) do
          nil ->
            {:ok, ["Org: #{org.slug}", "Identity provider: (none)"]}

          %{} = idp ->
            header = ["Org: #{org.slug}", "Type: #{idp["type"]}"]

            extras =
              idp
              |> Map.delete("type")
              |> Enum.sort_by(&elem(&1, 0))
              |> Enum.map(fn {k, v} -> "  #{k}: #{v}" end)

            {:ok, header ++ extras}
        end
    end
  end

  def run_command(%{command: :org_members, options: _options, args: [slug]}, _project_root) do
    alias ControlKeel.Accounts

    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:error, "Org not found: #{slug}"}

      org ->
        memberships = Accounts.list_memberships_for_org(org.id)

        rows =
          if memberships == [] do
            ["No members."]
          else
            Enum.map(memberships, fn m ->
              user = Accounts.get_user(m.user_id)
              email = if(user, do: user.email, else: "(deleted)")
              "  #{email}\trole=#{m.role}\tstatus=#{m.status}"
            end)
          end

        {:ok, ["Members of #{org.slug}:" | rows]}
    end
  end

  def run_command(%{command: :mcp_guardrails_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.Guardrails

    summary = Guardrails.summary()

    header = [
      "Cloud MCP content guardrails",
      "Enabled: #{summary.enabled}",
      "Active patterns: #{summary.pattern_count}",
      ""
    ]

    pattern_rows =
      if summary.patterns == [] do
        ["No patterns active."]
      else
        ["Patterns:"] ++ Enum.map(summary.patterns, &"  #{&1}")
      end

    allow_rows =
      if summary.allow_for_tools == [] do
        []
      else
        ["", "Allow-for-tools (skipped from scanning):"] ++
          Enum.map(summary.allow_for_tools, &"  #{&1}")
      end

    {:ok, header ++ pattern_rows ++ allow_rows}
  end

  def run_command(%{command: :mcp_registry_list, options: _options}, _project_root) do
    alias ControlKeel.Cloud.McpRegistry

    summary = McpRegistry.summary()
    entries = McpRegistry.entries()
    denylist = McpRegistry.denylist()

    header = [
      "Cloud MCP server registry",
      "Default policy: #{summary.default_policy}",
      "Allowlisted: #{summary.allowlist_count} (#{summary.requires_attestation} require attestation)",
      "Denylisted:  #{summary.denylist_count}",
      ""
    ]

    allow_rows =
      if entries == [] do
        ["Allowlist: (empty)"]
      else
        ["Allowlist:"] ++
          Enum.map(entries, fn e ->
            "  #{e.name}  attestation=#{e.attestation}#{format_url(e.url)}#{format_note(e.note)}"
          end)
      end

    deny_rows =
      if denylist == [] do
        ["Denylist: (empty)"]
      else
        ["Denylist:"] ++ Enum.map(denylist, &"  #{&1}")
      end

    {:ok, header ++ allow_rows ++ [""] ++ deny_rows}
  end

  def run_command(
        %{command: :mcp_registry_check, options: options, args: [server_name]},
        _project_root
      ) do
    alias ControlKeel.Cloud.McpRegistry

    attested? = Map.get(options, :attested, false)
    disposition = McpRegistry.lookup(server_name, attested?: attested?)

    line =
      case disposition do
        :allowed ->
          "ALLOWED: #{server_name}#{if attested?, do: " (attestation provided)", else: ""}"

        {:denied, reason} ->
          "DENIED:  #{server_name} (#{reason})"
      end

    {:ok, [line]}
  end

  def run_command(%{command: :telemetry_flush, options: options}, _project_root) do
    alias ControlKeel.Cloud.Sender

    limit_opts = if options[:limit], do: [limit: options[:limit]], else: []

    case Sender.flush(limit_opts) do
      {:ok, :no_endpoint, 0} ->
        {:ok,
         [
           "Cloud telemetry flush: skipped (no endpoint configured)",
           "Set :controlkeel, :cloud_telemetry_endpoint to enable upstream sync."
         ]}

      {:ok, :no_pending, 0} ->
        {:ok, ["Cloud telemetry flush: queue is empty"]}

      {:ok, :sent, count} ->
        {:ok, ["Cloud telemetry flush: sent #{count} event(s)"]}

      {:error, :not_connected, _} ->
        {:error,
         "Cloud telemetry flush failed: workspace not connected. Run `controlkeel cloud connect` first."}

      {:error, :network, count} ->
        {:error,
         "Cloud telemetry flush failed: network error (#{count} event(s) marked failed and will retry)"}

      {:error, {:server, status}, count} ->
        {:error,
         "Cloud telemetry flush failed: server returned #{status} (#{count} event(s) marked failed)"}
    end
  end

  def run_command(%{command: :telemetry_queue, options: options}, _project_root) do
    alias ControlKeel.Cloud.TelemetryQueue

    limit = Map.get(options, :limit, 20)
    pending = TelemetryQueue.pending(limit: limit)
    total = TelemetryQueue.pending_count()

    header = [
      "ControlKeel cloud telemetry queue",
      "Pending events: #{total}",
      "Showing: #{length(pending)}/#{total} (limit=#{limit})"
    ]

    rows =
      if pending == [] do
        ["  (queue is empty)"]
      else
        Enum.map(pending, fn event ->
          "  #{event.event_id}  #{event.kind}  workspace=#{event.workspace_id}  attempts=#{event.send_attempts}  queued_at=#{DateTime.to_iso8601(event.queued_at)}"
        end)
      end

    {:ok, header ++ rows}
  end

  def run_command(%{command: :telemetry_status, options: _options}, _project_root) do
    state = ControlKeel.Cloud.TelemetryConfig.load()
    enabled? = ControlKeel.Cloud.TelemetryConfig.enabled?(state)

    base = [
      "ControlKeel cloud telemetry",
      "Status: #{if enabled?, do: "enabled", else: "disabled"}",
      "Level: #{state.level}",
      "Source: #{state.source}",
      "Config path: #{state.path}",
      "Redaction policy version: #{state.redaction_policy_version}",
      "Schema version: #{state.schema_version}"
    ]

    workspace_line = if state.workspace_id, do: ["Workspace: #{state.workspace_id}"], else: []

    enabled_at_line =
      if state.enabled_at, do: ["Enabled at: #{DateTime.to_iso8601(state.enabled_at)}"], else: []

    error_line = if state.load_error, do: ["Load error: #{state.load_error}"], else: []

    {:ok, base ++ workspace_line ++ enabled_at_line ++ error_line}
  end

  def run_command(%{command: :agents_doctor, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    doctor = AgentExecution.doctor(root)
    snapshot = SetupAdvisor.snapshot(root)

    agent_lines =
      Enum.map(doctor["agents"], fn agent ->
        "  #{agent.id}: #{agent.execution_support} / #{agent.ck_runs_agent_via} attached=#{if(agent.attached, do: "yes", else: "no")} runnable=#{if(agent.runnable, do: "yes", else: "no")}"
      end)

    {:ok,
     [
       "Agent execution doctor",
       "Project root: #{doctor["project_root"]}",
       SetupAdvisor.detected_hosts_line(snapshot),
       "Attached agents: #{if(doctor["attached_agents"] == [], do: "none", else: Enum.join(doctor["attached_agents"], ", "))}",
       "Direct ready: #{length(doctor["direct_ready"])}",
       "Handoff ready: #{length(doctor["handoff_ready"])}",
       "Runtime ready: #{length(doctor["runtime_ready"])}",
       "Core loop: #{SetupAdvisor.core_loop()}",
       "Agents:"
       | agent_lines
     ]}
  end

  def run_command(%{command: :attach_doctor, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    doctor = AgentExecution.doctor(root)
    snapshot = SetupAdvisor.snapshot(root)
    provider_status = ProviderBroker.status(root)

    attached = Enum.filter(doctor["agents"], & &1.attached)
    runnable_attached = Enum.count(attached, & &1.runnable)

    attached_lines =
      if attached == [] do
        ["Attached agents: none (run `controlkeel attach <agent>`)."]
      else
        [
          "Attached agents: #{Enum.join(Enum.map(attached, & &1.id), ", ")}",
          "Runnable attached agents: #{runnable_attached}/#{length(attached)}",
          "Attached details:"
        ] ++
          Enum.map(attached, fn agent ->
            "  #{agent.id}: runnable=#{if(agent.runnable, do: "yes", else: "no")} support=#{agent.execution_support}/#{agent.ck_runs_agent_via}"
          end)
      end

    {:ok,
     [
       "Attach health check",
       "Project root: #{doctor["project_root"]}",
       SetupAdvisor.detected_hosts_line(snapshot),
       "Provider source: #{provider_status["selected_source"]}",
       "Provider: #{provider_status["selected_provider"]}",
       "Core loop: #{SetupAdvisor.core_loop()}",
       "Verification commands:",
       "  - controlkeel status",
       "  - controlkeel agents doctor",
       "  - controlkeel provider doctor"
     ] ++ attached_lines}
  end

  def run_command(%{command: :agents_list, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      agents = AgentExecution.list_agents(root)

      case format do
        "json" ->
          {:ok, [Jason.encode!(%{"agents" => agents})]}

        _ ->
          lines =
            ["Agents:"] ++
              Enum.map(agents, fn agent ->
                "  #{agent.id}: attached=#{if(agent.attached, do: "yes", else: "no")} runnable=#{if(agent.runnable, do: "yes", else: "no")} support=#{agent.execution_support}"
              end)

          {:ok, lines}
      end
    end
  end

  def run_command(%{command: :route_agent, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, task_title} <- require_string_option(options[:task], "task"),
         {:ok, risk_tier} <- optional_risk_tier(options[:risk_tier]) do
      router_opts =
        []
        |> maybe_put_cli_opt(:risk_tier, risk_tier)
        |> maybe_put_cli_opt(:budget_remaining_cents, options[:budget_remaining_cents])
        |> maybe_put_cli_opt(:allowed_agents, parse_allowed_agents(options[:allowed_agents]))
        |> maybe_put_cli_opt(:domain_pack, options[:domain_pack])

      case AgentRouter.route(task_title, router_opts) do
        {:ok, recommendation} ->
          case format do
            "json" ->
              {:ok, [Jason.encode!(%{"recommendation" => recommendation})]}

            _ ->
              {:ok,
               [
                 "Recommended agent: #{recommendation.agent}",
                 "Task type: #{recommendation.task_type}",
                 "Rationale: #{Enum.join(recommendation.rationale || [], " | ")}",
                 if((recommendation.warnings || []) == [],
                   do: "Warnings: none",
                   else: "Warnings: #{Enum.join(recommendation.warnings, " | ")}"
                 )
               ]}
          end

        {:error, :no_suitable_agent, message} ->
          {:error, message}
      end
    end
  end

  def run_command(%{command: :task_complete, args: [task_id]}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, updated_task} <- Mission.complete_task(task) do
      {:ok,
       ["Completed task ##{updated_task.id}: #{updated_task.title} (#{updated_task.status})"]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task not found."}

      {:error, :unresolved_findings, findings} ->
        {:error,
         "Task has #{length(findings)} unresolved findings; resolve or approve them before completing."}

      {:error, reason} ->
        {:error, "Failed to complete task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_claim, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, task_run} <-
           Platform.claim_task(task.id, nil, %{
             "execution_mode" => normalize_task_execution_mode(options[:execution_mode])
           }) do
      {:ok, ["Claimed task ##{task.id}: run ##{task_run.id} is #{task_run.status}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task not found."}

      {:error, reason} ->
        {:error, "Failed to claim task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_heartbeat, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, task_run} <-
           Platform.heartbeat_task(task.id, nil, %{
             "progress" => options[:progress],
             "note" => options[:note]
           }) do
      {:ok, ["Heartbeat recorded for task ##{task.id}: run ##{task_run.id}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to record heartbeat: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_checks, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, checks} <- decode_required_json_list(options[:checks], "checks"),
         {:ok, results} <- Platform.record_task_checks(task.id, nil, checks) do
      {:ok, ["Recorded #{length(results)} check result(s) for task ##{task.id}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to record checks: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :task_report, args: [task_id], options: options}, project_root) do
    with {:ok, task} <- task_in_current_session(project_root, task_id),
         {:ok, output} <- decode_optional_json_map(options[:output], "output"),
         {:ok, metadata} <- decode_optional_json_map(options[:metadata], "metadata"),
         {:ok, task_run} <-
           Platform.report_task(task.id, nil, %{
             "status" => options[:status] || "done",
             "output" => output,
             "metadata" => metadata
           }) do
      {:ok, ["Reported task ##{task.id}: run ##{task_run.id} now #{task_run.status}."]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, :not_found} ->
        {:error, "Task run not found; claim the task first."}

      {:error, reason} ->
        {:error, "Failed to report task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :run_task, args: [task_id], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, parsed_id} <- parse_id(task_id),
         {:ok, result} <- AgentExecution.run_task(parsed_id, agent_run_opts(options, root)) do
      {:ok, agent_execution_lines(result)}
    else
      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, {:policy_blocked, reason}} ->
        {:error, "Delegated execution blocked: #{reason}"}

      {:error, reason} ->
        {:error, "Failed to run task: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :run_session, args: [session_id], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, parsed_id} <- parse_id(session_id),
         {:ok, result} <- AgentExecution.run_session(parsed_id, agent_run_opts(options, root)) do
      session_lines =
        Enum.flat_map(result["results"], fn item ->
          [
            "  task ##{item["task_id"]}: #{item["status"]} via #{item["agent_id"] || "unknown"} (#{item["mode"] || "unknown"})"
          ]
        end)

      {:ok,
       [
         "Delegated session ##{result["session_id"]}.",
         "Project root: #{result["project_root"]}",
         "Task count: #{result["task_count"]}",
         "Results:"
         | session_lines
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to run session: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :session_list}, _project_root) do
    sessions = Mission.list_recent_sessions(20)

    lines =
      if sessions == [] do
        ["No missions found. Start one with: controlkeel init"]
      else
        ["Recent missions:"] ++
          Enum.map(sessions, fn session ->
            "##{session.id} #{session.title} — #{session.risk_tier} risk — workspace ##{session.workspace_id}"
          end)
      end

    {:ok, lines}
  end

  def run_command(%{command: :session_switch, args: [session_id]}, project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         %{} = target <- Mission.get_session(parsed_id),
         {:ok, binding, _current_session, _mode} <- ensure_local_project(project_root),
         updated <-
           binding
           |> Map.put("session_id", target.id)
           |> Map.put("workspace_id", target.workspace_id),
         {:ok, written} <-
           ProjectBinding.write_effective(updated, project_root,
             mode: binding_write_mode(binding)
           ),
         {:ok, _updated_session} <-
           Mission.attach_session_runtime_context(target.id, %{
             "project_root" => ProjectRoot.resolve(project_root)
           }) do
      {:ok,
       [
         "Switched ControlKeel project binding to mission ##{target.id}: #{target.title}.",
         "Project root: #{written["project_root"]}."
       ]}
    else
      {:error, :invalid_id} -> {:error, "Invalid mission id: #{session_id}"}
      nil -> {:error, "Mission not found: #{session_id}"}
      {:error, reason} -> {:error, "Could not switch mission: #{format_cli_error(reason)}"}
    end
  end

  def run_command(%{command: :me, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <- ensure_local_project(project_root) do
      session_id = options[:session_id] || default_session.id

      payload = ControlKeel.Learning.EngineerMirror.build(session_id)

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          {:ok, [render_engineer_mirror(payload)]}
      end
    end
  end

  def run_command(%{command: :context, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <- ensure_local_project(project_root) do
      session_id = options[:session_id] || default_session.id
      project_root_resolved = options[:project_root] || project_root

      args =
        %{
          "session_id" => session_id,
          "project_root" => ProjectRoot.resolve(project_root_resolved)
        }
        |> maybe_put_tool_int("task_id", options[:task_id])

      case CkContext.call(args) do
        {:ok, payload} ->
          case format do
            "json" -> {:ok, [Jason.encode!(payload)]}
            _ -> {:ok, [inspect(payload, pretty: true, limit: :infinity)]}
          end

        {:error, {:invalid_arguments, msg}} when is_binary(msg) ->
          {:error, msg}

        {:error, {:invalid_arguments, reason}} ->
          {:error, format_cli_error(reason)}

        {:error, reason} ->
          {:error, "Failed to load context: #{format_cli_error(reason)}"}
      end
    end
  end

  def run_command(%{command: :validate, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <- ensure_local_project(project_root) do
      content = options[:content]

      if not is_binary(content) or String.trim(content) == "" do
        {:error, "`--content` is required for controlkeel validate."}
      else
        args =
          %{
            "content" => content,
            "kind" => options[:kind] || "code",
            "session_id" => options[:session_id] || default_session.id
          }
          |> maybe_put_tool_int("task_id", options[:task_id])
          |> maybe_put_tool_string("path", options[:path])

        case CkValidate.call(args) do
          {:ok, payload} ->
            case format do
              "json" -> {:ok, [Jason.encode!(payload)]}
              _ -> {:ok, [inspect(payload, pretty: true, limit: :infinity)]}
            end

          {:error, {:invalid_arguments, msg}} when is_binary(msg) ->
            {:error, msg}

          {:error, {:invalid_arguments, reason}} ->
            {:error, format_cli_error(reason)}

          {:error, reason} ->
            {:error, "Validation failed: #{format_cli_error(reason)}"}
        end
      end
    end
  end

  def run_command(%{command: :status, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, binding, session, _mode} <- ensure_local_project(project_root) do
      metrics = Analytics.session_metrics(session.id) || %{}
      rolling_24h = Budget.rolling_24h_spend_cents(session.id)
      provider_status = ProviderBroker.status(project_root)
      autonomy = AutonomyLoop.session_autonomy_profile(session)
      outcome = AutonomyLoop.session_outcome_profile(session)
      improvement = AutonomyLoop.session_improvement_loop(session)
      active_task = current_session_task(session)
      workspace_context = session_workspace_context(session, project_root)
      augmentation = TaskAugmentation.build(session, active_task, workspace_context)
      security_summary = Mission.security_case_summary(session.findings)

      active_findings =
        Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))

      active_tasks = Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"]))

      help_lines =
        contextual_status_help_lines(session, active_task, active_findings, improvement)

      payload = %{
        "session" => %{
          "id" => session.id,
          "title" => session.title,
          "risk_tier" => session.risk_tier,
          "active_findings" => active_findings,
          "active_tasks" => active_tasks
        },
        "budget" => %{
          "spent" => format_money(session.spent_cents),
          "session_budget" => format_money(session.budget_cents),
          "rolling_24h" => format_money(rolling_24h),
          "daily_budget" => format_money(session.daily_budget_cents)
        },
        "autonomy_profile" => autonomy,
        "outcome_profile" => outcome,
        "current_task" => current_task_payload(active_task),
        "task_augmentation" => %{
          "status" => augmentation_status_line(augmentation),
          "available" => augmentation["available"] == true,
          "likely_paths" => augmentation["likely_paths"] || [],
          "search_terms" => augmentation["search_terms"] || []
        },
        "security_case_summary" => security_summary,
        "metrics" => %{
          "funnel_stage" => Analytics.stage_label(metrics[:funnel_stage]),
          "time_to_first_finding" => format_duration(metrics[:time_to_first_finding_seconds]),
          "total_findings" => metrics[:total_findings] || 0,
          "blocked_findings" => metrics[:blocked_findings_total] || 0
        },
        "provider_status" => %{
          "bootstrap_mode" => provider_status["bootstrap"]["mode"],
          "provider_source" => provider_status["selected_source"],
          "provider" => provider_status["selected_provider"],
          "auth_mode" => provider_status["selected_auth_mode"],
          "auth_owner" => provider_status["selected_auth_owner"],
          "execution_sandbox" => ExecutionSandbox.adapter_name([])
        },
        "proxy_urls" => %{
          "openai_responses" => Proxy.url(session, :openai, "/v1/responses"),
          "openai_chat" => Proxy.url(session, :openai, "/v1/chat/completions"),
          "openai_completions" => Proxy.url(session, :openai, "/v1/completions"),
          "openai_embeddings" => Proxy.url(session, :openai, "/v1/embeddings"),
          "openai_models" => Proxy.url(session, :openai, "/v1/models"),
          "openai_realtime" => Proxy.realtime_url(session, :openai, "/v1/realtime"),
          "anthropic_messages" => Proxy.url(session, :anthropic, "/v1/messages")
        },
        "attached_agents" => attached_agent_status_payload(binding),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          {:ok,
           [
             "Session: #{session.title} (##{session.id})",
             "Risk tier: #{session.risk_tier}",
             "Budget: #{format_money(session.spent_cents)} / #{format_money(session.budget_cents)} used",
             "Rolling 24h: #{format_money(rolling_24h)} / #{format_money(session.daily_budget_cents)}",
             "Active findings: #{active_findings}",
             "Active tasks: #{active_tasks}",
             "Autonomy: #{autonomy["label"]}",
             "Outcome: #{outcome["label"]} | #{outcome["metric"]}",
             "Current task: #{(active_task && active_task.title) || "No active task"}",
             "Task augmentation: #{augmentation_status_line(augmentation)}",
             "Security cases: #{security_case_status_line(security_summary)}",
             "Funnel stage: #{Analytics.stage_label(metrics[:funnel_stage])}",
             "Time to first finding: #{format_duration(metrics[:time_to_first_finding_seconds])}",
             "Total findings: #{metrics[:total_findings] || 0}",
             "Blocked findings: #{metrics[:blocked_findings_total] || 0}",
             "Bootstrap mode: #{provider_status["bootstrap"]["mode"]}",
             "Provider source: #{provider_status["selected_source"]}",
             "Provider: #{provider_status["selected_provider"]}",
             "Auth mode: #{provider_status["selected_auth_mode"]}",
             "Auth owner: #{provider_status["selected_auth_owner"]}",
             "Execution sandbox: #{ExecutionSandbox.adapter_name([])}",
             "OpenAI responses: #{Proxy.url(session, :openai, "/v1/responses")}",
             "OpenAI chat: #{Proxy.url(session, :openai, "/v1/chat/completions")}",
             "OpenAI completions: #{Proxy.url(session, :openai, "/v1/completions")}",
             "OpenAI embeddings: #{Proxy.url(session, :openai, "/v1/embeddings")}",
             "OpenAI models: #{Proxy.url(session, :openai, "/v1/models")}",
             "OpenAI realtime: #{Proxy.realtime_url(session, :openai, "/v1/realtime")}",
             "Anthropic messages: #{Proxy.url(session, :anthropic, "/v1/messages")}"
           ] ++
             attached_agent_status_lines(binding) ++ help_lines}
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
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

  def run_command(%{command: :findings, options: options}, project_root) do
    with {:ok, format} <- cli_output_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      findings =
        Mission.list_session_findings(session.id, %{
          severity: options[:severity],
          status: options[:status]
        })

      security_summary = Mission.security_case_summary(findings)

      active_total =
        Enum.count(session.findings, &(&1.status in ["open", "blocked", "escalated"]))

      filter_summary = findings_filter_summary(options)
      help_lines = findings_help_lines(findings, options)

      payload = %{
        "summary" => %{
          "matched" => length(findings),
          "active_findings_in_session" => active_total,
          "filter_summary" => filter_summary,
          "security_case_summary" => security_summary
        },
        "entries" =>
          Enum.map(findings, fn finding ->
            %{
              "id" => finding.id,
              "severity" => finding.severity,
              "status" => finding.status,
              "title" => finding.title,
              "rule_id" => finding.rule_id
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          if findings == [] do
            {:ok,
             [
               "Findings: 0 matched#{filter_summary}",
               "Active findings in session: #{active_total}",
               "Security cases: #{security_case_status_line(security_summary)}"
             ] ++ help_lines}
          else
            {:ok,
             [
               "Findings: #{length(findings)} matched#{filter_summary}",
               "Active findings in session: #{active_total}",
               "Security cases: #{security_case_status_line(security_summary)}"
             ] ++
               Enum.map(findings, fn finding ->
                 "##{finding.id} [#{finding.severity}/#{finding.status}] #{finding.title} (#{finding.rule_id})"
               end) ++ help_lines}
          end
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :approve, args: [finding_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(finding_id),
         finding when not is_nil(finding) <- Mission.get_finding(parsed_id),
         true <- finding.session_id == session.id || {:error, :wrong_session},
         {:ok, updated} <- Mission.approve_finding(finding) do
      {:ok, ["Approved finding ##{updated.id}: #{updated.title}"]}
    else
      {:error, :wrong_session} ->
        {:error, "That finding does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Finding id must be an integer."}

      nil ->
        {:error, "Finding not found."}

      {:error, reason} ->
        {:error, "Failed to approve finding: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :proofs, options: options}, project_root) do
    with {:ok, format} <- cli_output_format(options),
         {:ok, _binding, session, _mode} <- ensure_local_project(project_root) do
      browser =
        Mission.browse_proof_bundles(%{
          session_id: options[:session_id] || session.id,
          task_id: options[:task_id],
          deploy_ready: options[:deploy_ready]
        })

      help_lines = proofs_help_lines(browser.entries, options)

      payload = %{
        "summary" => %{
          "matched" => length(browser.entries),
          "session_proof_bundles" => browser.total_count,
          "deploy_ready_in_view" => Enum.count(browser.entries, & &1.deploy_ready),
          "filter_summary" => proofs_filter_summary(options)
        },
        "entries" =>
          Enum.map(browser.entries, fn proof ->
            %{
              "id" => proof.id,
              "version" => proof.version,
              "status" => proof.status,
              "task_id" => proof.task_id,
              "task_title" => proof.task.title,
              "risk_score" => proof.risk_score,
              "deploy_ready" => proof.deploy_ready
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          if browser.entries == [] do
            {:ok,
             [
               "Proof bundles: 0 matched#{proofs_filter_summary(options)}",
               "Session proof bundles: #{browser.total_count}",
               "Deploy-ready in view: 0"
             ] ++ help_lines}
          else
            {:ok,
             [
               "Proof bundles: #{length(browser.entries)} matched#{proofs_filter_summary(options)}",
               "Session proof bundles: #{browser.total_count}",
               "Deploy-ready in view: #{Enum.count(browser.entries, & &1.deploy_ready)}"
             ] ++
               Enum.map(browser.entries, fn proof ->
                 deploy = if proof.deploy_ready, do: "deploy-ready", else: "review-required"

                 "##{proof.id} v#{proof.version} [#{proof.status}] #{proof.task.title} (risk #{proof.risk_score}, #{deploy})"
               end) ++ help_lines}
          end
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :proof, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id) do
      cond do
        proof = Mission.get_proof_bundle(parsed_id) ->
          {:ok, [Jason.encode!(proof.bundle, pretty: true)]}

        true ->
          case Mission.proof_bundle(parsed_id) do
            {:ok, bundle} -> {:ok, [Jason.encode!(bundle, pretty: true)]}
            {:error, :not_found} -> {:error, "Proof bundle or task was not found."}
          end
      end
    else
      {:error, :invalid_id} ->
        {:error, "Proof id must be an integer."}
    end
  end

  def run_command(%{command: :audit_log, args: [session_id], options: options}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         format <- options[:format] || "json",
         true <- format in ["json", "csv", "pdf"] || {:error, :invalid_format},
         {:ok, %{export: export, payload: payload}} <-
           Platform.export_audit_log(parsed_id, format) do
      lines =
        case format do
          "pdf" ->
            [
              "Audit log exported for session ##{parsed_id}.",
              "Format: pdf",
              "Checksum: #{export.checksum}",
              "Artifact: #{export.artifact_path_or_ref}"
            ]

          _ ->
            [payload]
        end

      {:ok, lines}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, :invalid_format} ->
        {:error, "Audit log format must be json, csv, or pdf."}

      {:error, :renderer_unavailable} ->
        {:error, "PDF renderer is unavailable in this runtime."}

      {:error, :not_found} ->
        {:error, "Session not found."}

      {:error, reason} ->
        {:error, "Failed to export audit log: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_list, options: options}, project_root) do
    with {:ok, format} <- cli_output_format(options) do
      filter_opts = benchmark_filter_opts(options[:domain_pack])
      suites = Benchmark.list_suites(filter_opts)
      runs = Benchmark.list_recent_runs(filter_opts)
      subjects = Benchmark.available_subjects(project_root)
      help_lines = benchmark_list_help_lines(suites, runs, subjects)

      payload = %{
        "summary" => %{
          "suite_count" => length(suites),
          "subject_count" => length(subjects),
          "recent_run_count" => length(runs),
          "filter_summary" => benchmark_filter_summary(options)
        },
        "suites" =>
          Enum.map(suites, fn suite ->
            packs = Benchmark.domain_packs_for_suite(suite)

            %{
              "slug" => suite.slug,
              "version" => suite.version,
              "name" => suite.name,
              "scenario_count" => length(suite.scenarios),
              "domains" => format_domain_packs(packs)
            }
          end),
        "subjects" =>
          Enum.map(subjects, fn subject ->
            %{
              "id" => subject["id"],
              "type" => subject["type"],
              "label" => subject["label"]
            }
          end),
        "recent_runs" =>
          Enum.map(runs, fn run ->
            %{
              "id" => run.id,
              "suite_slug" => run.suite.slug,
              "status" => run.status,
              "catch_rate" => run.catch_rate,
              "baseline_subject" => run.baseline_subject
            }
          end),
        "suggested_next_steps" => help_lines_to_values(help_lines)
      }

      suite_lines =
        if suites == [] do
          [
            "Benchmark suites: 0#{benchmark_filter_summary(options)}",
            "Available subjects: #{length(subjects)}",
            "Recent runs: #{length(runs)}"
          ]
        else
          [
            "Benchmark suites: #{length(suites)}#{benchmark_filter_summary(options)}",
            "Available subjects: #{length(subjects)}",
            "Recent runs: #{length(runs)}",
            "Benchmark suites:"
            | Enum.map(suites, fn suite ->
                packs = Benchmark.domain_packs_for_suite(suite)

                "  #{suite.slug} v#{suite.version} — #{suite.name} (#{length(suite.scenarios)} scenarios; domains: #{format_domain_packs(packs)})"
              end)
          ]
        end

      subject_lines =
        [
          "",
          "Available subjects:"
          | Enum.map(subjects, fn subject ->
              "  #{subject["id"]} [#{subject["type"]}] #{subject["label"]}"
            end)
        ]

      run_lines =
        if runs == [] do
          ["", "No benchmark runs recorded yet."]
        else
          [
            "",
            "Recent runs:"
            | Enum.map(runs, fn run ->
                "  ##{run.id} #{run.suite.slug} [#{run.status}] catch #{run.catch_rate}% baseline #{run.baseline_subject}"
              end)
          ]
        end

      case format do
        "json" ->
          {:ok, [Jason.encode!(payload)]}

        _ ->
          {:ok, suite_lines ++ subject_lines ++ run_lines ++ help_lines}
      end
    else
      {:error, {:invalid_output_format, message}} ->
        {:error, message}
    end
  end

  def run_command(%{command: :benchmark_run, options: options}, project_root) do
    attrs = %{
      "suite" => options[:suite] || "vibe_failures_v1",
      "subjects" => options[:subjects],
      "baseline_subject" => options[:baseline_subject],
      "scenario_slugs" => options[:scenario_slugs],
      "domain_pack" => options[:domain_pack]
    }

    case Benchmark.run_suite(attrs, project_root) do
      {:ok, run} ->
        detail = Benchmark.run_detail_metrics(run)

        {:ok,
         [
           "Benchmark run ##{run.id} completed.",
           "Suite: #{run.suite.slug}",
           "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
           "Subjects: #{Enum.join(run.subjects, ", ")}",
           "Status: #{run.status}",
           "Catch rate: #{run.catch_rate}%",
           "Block rate: #{detail.block_rate}%",
           "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
           "Average overhead: #{format_percent(run.average_overhead_percent)}"
         ]}

      {:error, :suite_not_found} ->
        {:error, "Benchmark suite was not found."}

      {:error, reason} ->
        {:error, "Failed to run benchmark: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_show, args: [id]}, _project_root) do
    with {:ok, run_id} <- parse_id(id),
         %{} = run <- Benchmark.get_run(run_id) do
      detail = Benchmark.run_detail_metrics(run)

      subject_lines =
        run.results
        |> Enum.group_by(& &1.subject)
        |> Enum.map(fn {subject, results} ->
          catches = Enum.count(results, &(&1.findings_count > 0))
          blocked = Enum.count(results, &(&1.decision == "block"))
          "  #{subject}: #{catches} caught, #{blocked} blocked, #{length(results)} total"
        end)

      {:ok,
       [
         "Benchmark run ##{run.id}",
         "Suite: #{run.suite.name} (#{run.suite.slug})",
         "Domains: #{format_domain_packs(Benchmark.domain_packs_for_run(run))}",
         "Status: #{run.status}",
         "Baseline subject: #{run.baseline_subject}",
         "Catch rate: #{run.catch_rate}%",
         "Block rate: #{detail.block_rate}%",
         "Expected rule hit rate: #{detail.expected_rule_hit_rate}%",
         "Median latency: #{format_ms(run.median_latency_ms)}",
         "Average overhead: #{format_percent(run.average_overhead_percent)}",
         "Subjects:"
         | subject_lines
       ] ++ benchmark_show_help_lines(run)}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      nil ->
        {:error, "Benchmark run not found."}
    end
  end

  def run_command(
        %{command: :benchmark_import, args: [run_id, subject, file_path]},
        _project_root
      ) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, contents} <- File.read(file_path),
         {:ok, payload} <- Jason.decode(contents),
         {:ok, run} <- Benchmark.import_result(parsed_id, subject, payload) do
      {:ok,
       [
         "Imported benchmark output for #{subject} into run ##{run.id}.",
         "Run status: #{run.status}",
         "Catch rate: #{run.catch_rate}%"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :enoent} ->
        {:error, "Benchmark import file was not found."}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Benchmark import file must be valid JSON: #{Exception.message(error)}"}

      {:error, :scenario_slug_required} ->
        {:error, "Benchmark import payload must include `scenario_slug`."}

      {:error, :result_not_found} ->
        {:error,
         "No matching benchmark result slot exists for that run, subject, and scenario_slug."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}

      {:error, reason} ->
        {:error, "Failed to import benchmark output: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :benchmark_export, args: [run_id], options: options}, _project_root) do
    with {:ok, parsed_id} <- parse_id(run_id),
         {:ok, output} <- Benchmark.export_run(parsed_id, options[:format] || "json") do
      {:ok, [output]}
    else
      {:error, :invalid_id} ->
        {:error, "Benchmark run id must be an integer."}

      {:error, :not_found} ->
        {:error, "Benchmark run was not found."}
    end
  end

  def run_command(%{command: :service_account_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         scopes = options[:scopes] || "admin",
         {:ok, %{service_account: account, token: token}} <-
           Platform.create_service_account(workspace_id, %{
             "name" => name,
             "scopes" => scopes
           }) do
      {:ok,
       [
         "Created service account ##{account.id} for workspace ##{workspace_id}.",
         "Name: #{account.name}",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}",
         "Token: #{token}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      accounts = Platform.list_service_accounts(workspace_id)

      lines =
        if accounts == [] do
          ["No service accounts found for workspace ##{workspace_id}."]
        else
          [
            "Service accounts for workspace ##{workspace_id}:"
            | Enum.map(accounts, fn account ->
                "  ##{account.id} #{account.name} [#{account.status}] client: #{ProtocolAccess.oauth_client_id(account)} scopes: #{Enum.join(ControlKeel.Platform.ServiceAccount.scope_list(account), ", ")}"
              end)
          ]
        end

      {:ok, lines}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :service_account_revoke, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, account} <- Platform.revoke_agent_identity(parsed_id) do
      {:ok, ["Revoked service account ##{account.id}. Audit event recorded."]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to revoke service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :service_account_rotate, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, %{service_account: account, token: token}} <-
           Platform.rotate_agent_identity_token(parsed_id) do
      {:ok,
       [
         "Rotated service account ##{account.id}. Audit event recorded.",
         "OAuth client id: #{ProtocolAccess.oauth_client_id(account)}",
         "Token: #{token}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Service account id must be an integer."}

      {:error, :not_found} ->
        {:error, "Service account not found."}

      {:error, reason} ->
        {:error, "Failed to rotate service account: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :workspace_tool_policy_get, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      policy = Accounts.get_workspace_tool_policy(workspace_id)
      mode = (policy && policy.mode) || "inherit"
      tools = (policy && WorkspaceToolPolicy.decode_tools(policy)) || []

      lines = [
        "Tool policy for workspace ##{workspace_id}:",
        "  Mode: #{mode}"
      ]

      lines =
        if tools == [] do
          lines
        else
          lines ++ ["  Tools: #{Enum.join(tools, ", ")}"]
        end

      {:ok, lines}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :workspace_tool_policy_set, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, mode} <- require_string_option(options[:mode], "mode") do
      tools =
        case options[:tools] do
          nil -> []
          t -> String.split(t, ",") |> Enum.map(&String.trim/1)
        end

      case Accounts.set_workspace_tool_policy(workspace_id, mode, tools) do
        {:ok, policy} ->
          decoded = WorkspaceToolPolicy.decode_tools(policy)

          {:ok,
           [
             "Tool policy updated for workspace ##{workspace_id}.",
             "  Mode: #{policy.mode}",
             "  Tools: #{if decoded == [], do: "(none)", else: Enum.join(decoded, ", ")}"
           ]}

        {:error, changeset} ->
          {:error, "Failed to set tool policy: #{inspect(changeset)}"}
      end
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :policy_set_create, options: options}, _project_root) do
    with {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, rules} <- load_rules_payload(options[:rules_file]),
         {:ok, policy_set} <-
           Platform.create_policy_set(%{
             "name" => name,
             "scope" => options[:scope] || "workspace",
             "description" => options[:description],
             "rules" => rules
           }) do
      {:ok,
       [
         "Created policy set ##{policy_set.id}.",
         "Name: #{policy_set.name}",
         "Rules: #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :policy_set_list, options: options}, _project_root) do
    workspace_id = options[:workspace_id]
    policy_sets = Platform.list_policy_sets()

    assignment_lines =
      if workspace_id do
        ["", "Assignments:"] ++
          Enum.map(Platform.list_workspace_policy_sets(workspace_id), fn assignment ->
            "  workspace ##{workspace_id} -> ##{assignment.policy_set_id} #{assignment.policy_set.name} precedence #{assignment.precedence}"
          end)
      else
        []
      end

    {:ok,
     [
       "Policy sets:"
       | Enum.map(policy_sets, fn policy_set ->
           "  ##{policy_set.id} #{policy_set.name} [#{policy_set.status}] #{length(ControlKeel.Platform.PolicySet.rule_entries(policy_set))} rules"
         end)
     ] ++ assignment_lines}
  end

  def run_command(
        %{command: :policy_set_apply, args: [workspace_id, policy_set_id], options: options},
        _project_root
      ) do
    with {:ok, parsed_workspace_id} <- parse_id(workspace_id),
         {:ok, parsed_policy_set_id} <- parse_id(policy_set_id),
         {:ok, assignment} <-
           Platform.apply_policy_set(parsed_workspace_id, parsed_policy_set_id, %{
             "precedence" => options[:precedence] || 100,
             "enabled" => true
           }) do
      {:ok,
       [
         "Applied policy set ##{assignment.policy_set_id} to workspace ##{assignment.workspace_id}.",
         "Precedence: #{assignment.precedence}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Workspace id and policy set id must be integers."}

      {:error, reason} ->
        {:error, "Failed to apply policy set: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_create, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id"),
         {:ok, name} <- require_string_option(options[:name], "name"),
         {:ok, url} <- require_string_option(options[:url], "url"),
         events <- options[:events] || Enum.join(Platform.webhook_events(), ","),
         {:ok, webhook} <-
           Platform.create_webhook(workspace_id, %{
             "name" => name,
             "url" => url,
             "secret" => options[:secret],
             "subscribed_events" => events
           }) do
      {:ok,
       [
         "Created webhook ##{webhook.id} for workspace ##{workspace_id}.",
         "Events: #{Enum.join(ControlKeel.Platform.IntegrationWebhook.event_list(webhook), ", ")}"
       ]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}

      {:error, reason} ->
        {:error, "Failed to create webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :webhook_list, options: options}, _project_root) do
    with {:ok, workspace_id} <- require_integer_option(options[:workspace_id], "workspace-id") do
      webhooks = Platform.list_webhooks(workspace_id)
      deliveries = Platform.list_deliveries(workspace_id)

      {:ok,
       [
         "Webhooks for workspace ##{workspace_id}:"
         | Enum.map(webhooks, fn webhook ->
             "  ##{webhook.id} #{webhook.name} [#{webhook.status}] #{webhook.url}"
           end)
       ] ++
         ["", "Recent deliveries:"] ++
         Enum.map(deliveries, fn delivery ->
           "  ##{delivery.id} #{delivery.event} [#{delivery.status}] attempts #{delivery.attempts}"
         end)}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :webhook_replay, args: [id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(id),
         {:ok, delivery} <- Platform.replay_webhook(parsed_id) do
      {:ok,
       [
         "Replayed webhook ##{parsed_id}.",
         "Latest delivery status: #{delivery.status}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Webhook id must be an integer."}

      {:error, :not_found} ->
        {:error, "Webhook or delivery not found."}

      {:error, reason} ->
        {:error, "Failed to replay webhook: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :graph_show, args: [session_id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id) do
      graph = Platform.ensure_session_graph(parsed_id)

      edge_lines =
        Enum.map(graph.edges, fn edge ->
          "  #{edge.from_task_id} -> #{edge.to_task_id} [#{edge.dependency_type}]"
        end)

      {:ok,
       [
         "Task graph for session ##{parsed_id}:",
         "Ready tasks: #{Enum.join(Enum.map(graph.ready_task_ids, &to_string/1), ", ")}",
         "Edges:"
         | edge_lines
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}
    end
  end

  def run_command(%{command: :execute_session, args: [session_id]}, _project_root) do
    with {:ok, parsed_id} <- parse_id(session_id),
         {:ok, graph} <- Platform.execute_session(parsed_id) do
      {:ok,
       [
         "Executed scheduling for session ##{parsed_id}.",
         "Ready tasks: #{Enum.join(Enum.map(graph.ready_task_ids, &to_string/1), ", ")}",
         "Task runs: #{length(graph.task_runs)}"
       ]}
    else
      {:error, :invalid_id} ->
        {:error, "Session id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to execute session: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :worker_start, options: options}, _project_root) do
    with {:ok, token} <-
           require_string_option(options[:service_account_token], "service-account-token") do
      case Platform.Worker.start(token, interval: options[:interval] || 2_000) do
        {:error, :unauthorized} ->
          {:error, "Invalid service account token."}

        other ->
          other
      end
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option}"}
    end
  end

  def run_command(%{command: :provider_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Project root: #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
       "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Bootstrap mode: #{status["bootstrap"]["mode"]}",
       "Profiles:"
     ] ++
       Enum.map(status["profiles"], fn profile ->
         "  #{profile["provider"]}: configured=#{if(profile["configured"], do: "yes", else: "no")} env=#{if(profile["env_override"], do: "yes", else: "no")} default=#{if(profile["default"], do: "yes", else: "no")} model=#{profile["model"] || "n/a"} base_url=#{profile["base_url"] || "default"}"
       end)}
  end

  def run_command(%{command: :registry_sync_acp}, _project_root) do
    case ACPRegistry.sync() do
      {:ok, status} ->
        {:ok,
         [
           "Refreshed ACP registry cache.",
           "Source: #{status["registry_url"]}",
           "Fetched at: #{status["fetched_at"]}",
           "Entries: #{status["entry_count"]}",
           "Matched integrations: #{status["matched_integrations"]}",
           "Cache: #{status["cache_path"]}"
         ]}

      {:error, reason} ->
        {:error, "Failed to refresh ACP registry cache: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :registry_status_acp}, _project_root) do
    status = ACPRegistry.status()

    {:ok,
     [
       "ACP registry cache status:",
       "Source: #{status["registry_url"]}",
       "Fetched at: #{status["fetched_at"] || "never"}",
       "Entries: #{status["entry_count"]}",
       "Matched integrations: #{status["matched_integrations"]}",
       "Stale: #{if(status["stale"], do: "yes", else: "no")}",
       "Cache: #{status["cache_path"]}"
     ]}
  end

  def run_command(%{command: :sandbox_status}, _project_root) do
    adapters = ExecutionSandbox.supported_adapters()

    current_adapter_name = ExecutionSandbox.adapter_name([])

    current =
      Map.get(
        Enum.find(adapters, fn a -> a[:id] == current_adapter_name end) || %{},
        :name,
        "Unknown"
      )

    adapter_lines =
      Enum.map(adapters, fn adapter ->
        available = if adapter[:available], do: "available", else: "not available"
        marker = if adapter[:id] == ExecutionSandbox.adapter_name([]), do: " (active)", else: ""
        "  #{adapter[:name]} [#{adapter[:id]}]: #{available}#{marker}"
      end)

    {:ok,
     [
       "Execution sandbox adapters:",
       "Active: #{current}"
     ] ++ adapter_lines}
  end

  def run_command(%{command: :sandbox_config, options: %{adapter: adapter}}, _project_root) do
    valid_adapters = Enum.map(ExecutionSandbox.supported_adapters(), & &1[:id])

    if adapter in valid_adapters do
      config_path = RuntimePaths.config_path()
      config = read_json_config(config_path)
      updated = Map.put(config, "execution_sandbox", adapter)

      File.mkdir_p!(Path.dirname(config_path))
      File.write!(config_path, Jason.encode!(updated, pretty: true) <> "\n")

      {:ok, ["Execution sandbox set to: #{adapter}", "Config written to: #{config_path}"]}
    else
      {:error,
       "Unknown sandbox adapter: #{adapter}. Valid adapters: #{Enum.join(valid_adapters, ", ")}"}
    end
  end

  def run_command(%{command: :provider_show, options: options}, project_root) do
    root = options[:project_root] || project_root
    status = ProviderBroker.status(root)

    {:ok,
     [
       "Provider status for #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Selected model: #{status["selected_model"] || "n/a"}",
       "Selected base URL: #{selected_base_url(status)}",
       "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
       "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
       "Integrity posture: #{get_in(status, ["selected_trust_profile", "integrity_posture"]) || "unknown"}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Reason: #{status["reason"]}",
       "Fallback chain: #{Enum.join(status["fallback_chain"], " -> ")}"
     ] ++
       Enum.map(status["provider_chain"], fn resolution ->
         "  #{resolution["source"]}: #{resolution["provider"]} (#{resolution["model"] || "default"}) base_url=#{resolution["base_url"] || "default"} [#{resolution["auth_mode"]}/#{resolution["auth_owner"]}] trust=#{get_in(resolution, ["trust_profile", "trust_boundary"]) || "unknown"} risk=#{get_in(resolution, ["trust_profile", "intermediary_risk"]) || "unknown"}"
       end)}
  end

  def run_command(%{command: :provider_doctor, options: options}, project_root) do
    root = options[:project_root] || project_root
    doctor = ProviderBroker.doctor(root)
    status = doctor["status"]

    {:ok,
     [
       "Provider doctor for #{status["project_root"]}",
       "Selected source: #{status["selected_source"]}",
       "Selected provider: #{status["selected_provider"]}",
       "Trust boundary: #{get_in(status, ["selected_trust_profile", "trust_boundary"]) || "unknown"}",
       "Intermediary risk: #{get_in(status, ["selected_trust_profile", "intermediary_risk"]) || "unknown"}",
       "Auth mode: #{status["selected_auth_mode"]}",
       "Auth owner: #{status["selected_auth_owner"]}",
       "Bootstrap mode: #{status["bootstrap"]["mode"]}"
     ] ++ Enum.map(doctor["suggestions"], &"  #{&1}")}
  end

  def run_command(%{command: :provider_default, args: [source], options: options}, project_root) do
    scope = options[:scope] || "user"
    root = options[:project_root] || project_root

    case ProviderBroker.set_default_source(source, scope: scope, project_root: root) do
      {:ok, _config} ->
        {:ok, ["Set default provider source to #{source} for #{scope} scope."]}

      {:error, reason} ->
        {:error, "Failed to set default provider source: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_base_url, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_BASE_URL")

    with {:ok, base_url} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_base_url(provider, base_url) do
      {:ok, ["Stored base URL for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_BASE_URL"}

      {:error, reason} ->
        {:error, "Failed to store provider base URL: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_model, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_MODEL")

    with {:ok, model} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_model(provider, model) do
      {:ok, ["Stored model for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_MODEL"}

      {:error, reason} ->
        {:error, "Failed to store provider model: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_key, args: [provider], options: options},
        _project_root
      ) do
    value = options[:value] || System.get_env("CONTROLKEEL_PROVIDER_KEY")

    with {:ok, key} <- require_string_option(value, "value"),
         {:ok, _config} <- ProviderBroker.set_key(provider, key) do
      {:ok, ["Stored provider key for #{provider}."]}
    else
      {:error, {:missing_option, option}} ->
        {:error, "Missing required option --#{option} or CONTROLKEEL_PROVIDER_KEY"}

      {:error, reason} ->
        {:error, "Failed to store provider key: #{inspect(reason)}"}
    end
  end

  def run_command(
        %{command: :provider_set_fallback_chain, args: providers},
        _project_root
      )
      when providers != [] do
    case ProviderConfig.set_fallback_chain(providers) do
      {:ok, _config} ->
        {:ok, ["Fallback chain set: #{Enum.join(providers, " → ")}"]}

      {:error, {:unknown_providers, bad}} ->
        {:error,
         "Unknown provider(s): #{Enum.join(bad, ", ")}. Allowed: #{Enum.join(ProviderConfig.allowed_providers(), ", ")}"}

      {:error, reason} ->
        {:error, "Failed to set fallback chain: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :provider_set_fallback_chain, args: []}, _project_root) do
    {:error,
     "Provide at least one provider: controlkeel provider set-fallback-chain <p1> [p2 ...]"}
  end

  def run_command(%{command: :bootstrap, options: options}, project_root) do
    root = resolve_project_root(options, project_root)
    overrides = %{"agent" => options[:agent] || "claude"}

    case LocalProject.load_or_bootstrap(root, overrides,
           ephemeral_ok: options[:ephemeral_ok] != false
         ) do
      {:ok, binding, session, mode} ->
        {:ok,
         [
           "Bootstrapped ControlKeel for #{binding["project_root"]}",
           "Session: #{session.title} (##{session.id})",
           "Binding mode: #{mode}",
           "Binding path: #{ProjectBinding.bootstrap_summary(root)["binding_path"]}"
         ] ++ bootstrap_lines(root)}

      {:error, reason} ->
        {:error, "Failed to bootstrap ControlKeel: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :pause, args: [task_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session},
         {:ok, %{task: updated, resume_packet: packet}} <- Mission.pause_task(task, "cli") do
      {:ok,
       [
         "Paused task ##{updated.id}: #{updated.title}",
         Jason.encode!(packet, pretty: true)
       ]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to pause task: #{inspect(reason)}"}

      nil ->
        {:error, "Task not found."}

      _error ->
        {:error, "Failed to pause task."}
    end
  end

  def run_command(%{command: :resume, args: [task_id]}, project_root) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session},
         {:ok, %{task: updated, resume_packet: packet}} <- Mission.resume_task(task, "cli") do
      {:ok,
       [
         "Resumed task ##{updated.id}: #{updated.title}",
         Jason.encode!(packet, pretty: true)
       ]}
    else
      {:error, :wrong_session} ->
        {:error, "That task does not belong to the current governed session."}

      {:error, :invalid_id} ->
        {:error, "Task id must be an integer."}

      {:error, reason} ->
        {:error, "Failed to resume task: #{inspect(reason)}"}

      nil ->
        {:error, "Task not found."}

      _error ->
        {:error, "Failed to resume task."}
    end
  end

  def run_command(%{command: :memory_search, args: [query], options: options}, project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        result =
          Memory.search(query, %{
            workspace_id: session.workspace_id,
            session_id: options[:session_id] || session.id,
            record_type: options[:type]
          })

        if result.entries == [] do
          {:ok, ["No memory records matched the search query."]}
        else
          {:ok,
           Enum.map(result.entries, fn record ->
             "[#{record.record_type}] #{record.title} (score #{Float.round(record.score, 2)})"
           end)}
        end

      {:error, reason} ->
        {:error, "Failed to load local project: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_list, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root)
    selected_target = options[:target]

    skills =
      if selected_target do
        Enum.filter(analysis.skills, &(selected_target in (&1.compatibility_targets || [])))
      else
        analysis.skills
      end

    with {:ok, format} <- effective_cli_format(options) do
      case format do
        "json" ->
          {:ok,
           [
             Jason.encode!(
               skills_list_payload(root, selected_target, skills, analysis.diagnostics)
             )
           ]}

        _text ->
          {:ok, format_skills_list(skills, analysis.diagnostics)}
      end
    else
      {:error, reason} -> {:error, format_cli_error(reason)}
    end
  end

  def run_command(%{command: :skills_validate, options: options}, project_root) do
    root = options[:project_root] || project_root
    result = Skills.validate(root)

    {:ok,
     [
       "Skills valid: #{if(result.valid?, do: "yes", else: "no")}",
       "Total skills: #{result.total}",
       "Warnings: #{result.warning_count}",
       "Errors: #{result.error_count}"
     ] ++
       Enum.map(result.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :skills_export, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.export(target, root, scope: options[:scope]) do
      {:ok, plan} ->
        {:ok,
         [
           "Exported #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill export target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to export skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    target = options[:target] || "open-standard"

    case Skills.install(target, root, scope: options[:scope]) do
      {:ok, %{destination: destination} = result} ->
        lines = [
          "Installed #{result.target} skills.",
          "Destination: #{destination}"
        ]

        lines =
          if Map.has_key?(result, :agent_destination) do
            lines ++ ["Agent destination: #{result.agent_destination}"]
          else
            lines
          end

        {:ok, lines}

      {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
        {:ok,
         [
           "Prepared #{plan.target} bundle.",
           "Output: #{plan.output_dir}"
         ] ++ Enum.map(plan.instructions, &"  #{&1}")}

      {:error, :unknown_target} ->
        {:error, "Unknown skill install target: #{target}"}

      {:error, reason} ->
        {:error, "Failed to install skills: #{inspect(reason)}"}
    end
  end

  def run_command(%{command: :skills_doctor, options: options}, project_root) do
    root = options[:project_root] || project_root
    analysis = Skills.analyze(root, report_identical_duplicates: true)
    integrations = Skills.agent_integrations()
    provider_status = ProviderBroker.status(root)

    attach_clients =
      integrations
      |> Enum.filter(&(&1.support_class == "attach_client"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    runtimes =
      integrations
      |> Enum.filter(&(&1.support_class == "headless_runtime"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    frameworks =
      integrations
      |> Enum.filter(&(&1.support_class == "framework_adapter"))
      |> Enum.map(& &1.label)
      |> Enum.join(", ")

    manifests = Skills.export_manifests(root)

    manifest_lines =
      case manifests do
        [] ->
          ["Export manifests: none (no controlkeel/dist/*/.controlkeel-manifest.json found)."]

        list ->
          ["Export manifests: #{length(list)}"] ++
            Enum.map(Enum.take(list, 10), fn %{path: path, manifest: manifest} ->
              target = Map.get(manifest, "target") || "unknown"
              scope = Map.get(manifest, "scope") || "unknown"
              ver = Map.get(manifest, "controlkeel_version") || "unknown"
              at = Map.get(manifest, "installed_at") || "unknown"
              rel = Path.relative_to(path, Path.expand(root))
              "  - #{target} (scope=#{scope}, ck=#{ver}, at=#{at}) — #{rel}"
            end)
      end

    duplicate_copy_count =
      Enum.count(analysis.diagnostics, &(&1.code == "duplicate_skill_copy"))

    token_hint =
      if duplicate_copy_count > 0 do
        [
          "",
          "⚠️  TOKEN OPTIMIZATION WARNING:",
          "  Found #{duplicate_copy_count} duplicate skill copies wasting tokens.",
          "  Run 'controlkeel token audit' for detailed analysis and recommendations.",
          "  Run 'controlkeel token audit --mode skills' to see skill-specific optimization guidance."
        ]
      else
        []
      end

    {:ok,
     [
       "Project root: #{Path.expand(root)}",
       "Trusted project skills: #{if(analysis.trusted_project?, do: "yes", else: "no")}",
       "Catalog size: #{length(analysis.skills)}",
       "Duplicate identical skill copies: #{duplicate_copy_count}",
       "Hint: remove duplicate skill directories to reduce MCP host token overhead"
     ] ++
       token_hint ++
       [
         "Provider source: #{provider_status["selected_source"]}",
         "Provider: #{provider_status["selected_provider"]}",
         "Auth mode: #{provider_status["selected_auth_mode"]}",
         "Auth owner: #{provider_status["selected_auth_owner"]}",
         "Bootstrap mode: #{provider_status["bootstrap"]["mode"]}",
         "Attachable clients: #{attach_clients}",
         "Headless runtimes: #{if(runtimes == "", do: "none", else: runtimes)}",
         "Framework adapters: #{if(frameworks == "", do: "none", else: frameworks)}"
       ] ++
       manifest_lines ++
       Enum.map(analysis.diagnostics, fn diagnostic ->
         "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
       end)}
  end

  def run_command(%{command: :token_audit, options: options}, project_root) do
    root = options[:project_root] || project_root
    mode = options[:mode] || "full"
    format = options[:format] || "text"

    case mode do
      mode when mode in ["full", "rules", "skills", "tools"] ->
        audit_result =
          ControlKeel.MCP.Tools.CkTokenAudit.call(%{
            "project_root" => root,
            "mode" => mode
          })

        case audit_result do
          {:ok, result} ->
            output_lines = format_token_audit(result, mode, format)
            {:ok, output_lines}

          {:error, error} ->
            {:error, ["Token audit failed: #{inspect(error)}"]}
        end

      _ ->
        {:error, ["Invalid mode: #{mode}. Use: full, rules, skills, or tools"]}
    end
  end

  def run_command(%{command: :tool_groups_suggest, options: options}, project_root) do
    root = options[:project_root] || project_root
    format = options[:format] || "text"
    apply_preference = options[:apply] || false

    case ControlKeel.MCP.ToolGroupTracker.suggest_groups(root) do
      %{suggested: groups, reason: reason, usage_stats: stats} ->
        output_lines = format_tool_groups_suggest(groups, reason, stats, format)

        if apply_preference do
          case ControlKeel.ProjectBinding.put_tool_groups(root, groups) do
            {:ok, _binding} ->
              {:ok, output_lines ++ ["", "✓ Tool groups preference saved to project binding"]}

            {:error, error} ->
              {:error, output_lines ++ ["", "✗ Failed to save preference: #{inspect(error)}"]}
          end
        else
          {:ok, output_lines}
        end

      _ ->
        {:error, ["Failed to suggest tool groups"]}
    end
  end

  def run_command(%{command: :watch, options: options}, project_root) do
    if options[:status] do
      run_command(%{command: :status, options: %{}, args: []}, project_root)
    else
      interval = Keyword.get(options, :interval, 2_000)

      case ensure_local_project(project_root) do
        {:ok, _binding, session, _mode} ->
          IO.puts("")
          IO.puts("ControlKeel Watch — session ##{session.id}: #{session.title}")
          IO.puts("  Polling every #{interval}ms  |  Ctrl+C to exit")
          IO.puts(String.duplicate("─", 60))
          watch_loop(session.id, MapSet.new(), interval)

        {:error, reason} ->
          {:error, "Failed to load local project: #{inspect(reason)}"}
      end
    end
  end

  def run_command(%{command: :mcp, options: options}, project_root) do
    root = Path.expand(options[:project_root] || project_root)

    # MCP.Server is supervised first when CK_MCP_MODE (see Application); stdin reads
    # run while Repo boots. ensure_local_project stays async so binding/skills work
    # does not block the Mix process here. Skip AttachedAgentSync during bootstrap.
    File.cd!(root, fn ->
      case ensure_stdio_server_running(2_000) do
        pid when is_pid(pid) ->
          ref = Process.monitor(pid)

          _ =
            Task.start(fn ->
              case ensure_local_project(root, %{}, sync_attached_agents: false) do
                {:ok, _, _, _} ->
                  :ok

                {:error, reason} ->
                  Logger.error(
                    "[MCP] bootstrap failed (some tools may fail until fixed): #{inspect(reason)}"
                  )
              end
            end)

          receive do
            {:DOWN, ^ref, :process, ^pid, :normal} ->
              :ok

            {:DOWN, ^ref, :process, ^pid, :shutdown} ->
              :ok

            {:DOWN, ^ref, :process, ^pid, reason} ->
              {:error, "MCP server stopped: #{inspect(reason)}"}
          end

        nil ->
          {:error,
           "ControlKeel MCP stdio server is not running. Ensure CK_MCP_MODE is set before the application starts (see mix ck.mcp and bin/controlkeel-mcp)."}
      end
    end)
  end

  def run_command(%{command: :deploy_analyze, options: options}, project_root) do
    root = options[:project_root] || project_root

    case Advisor.analyze(root) do
      {:ok, result} ->
        platform_lines =
          Enum.map_join(result.platforms, "\n", fn p ->
            "  - " <> p.name <> " (" <> p.url <> ")"
          end)

        generator_lines =
          Enum.map_join(result.generators, "\n", fn g ->
            "  - " <> g.name <> " (" <> g.filename <> ")"
          end)

        lines =
          ["Stack: " <> to_string(result.stack), ""] ++
            ["Compatible platforms:", platform_lines, ""] ++
            [
              "Monthly cost estimate: $" <>
                to_string(result.monthly_cost_range.low) <>
                " - $" <> to_string(result.monthly_cost_range.high),
              ""
            ] ++
            ["Generated files:", generator_lines]

        {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_cost, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "static", deployment_stacks(), "stack"),
         {:ok, tier} <- parse_atom_option(options[:tier] || "free", hosting_tiers(), "tier"),
         {:ok, db_tier} <-
           parse_atom_option(options[:db_tier] || "managed_small", database_tiers(), "db_tier") do
      needs_db = options[:needs_db] || false
      bandwidth = options[:bandwidth] || 10
      storage = options[:storage] || 1

      case HostingCost.estimate(
             stack: stack,
             tier: tier,
             needs_db: needs_db,
             db_tier: db_tier,
             expected_bandwidth_gb: bandwidth,
             expected_storage_gb: storage
           ) do
        {:ok, estimates} ->
          lines =
            Enum.map(estimates, fn e ->
              fit = if e.fits_stack, do: "check", else: " "

              "$" <>
                to_string(Float.round(e.total_monthly_usd, 2)) <>
                " [#{fit}] " <> e.name <> " - " <> e.notes
            end)

          {:ok, ["Hosting cost estimates (stack: #{stack}):", "" | lines]}
      end
    end
  end

  def run_command(%{command: :deploy_dns, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.dns_ssl_guide(stack)

      lines =
        ["DNS Setup for #{stack}:", ""] ++
          Enum.map(guide.dns_setup, &("  " <> &1)) ++
          ["", "SSL Setup:", ""] ++
          Enum.map(guide.ssl_setup, &("  " <> &1))

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_migration, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.db_migration_guide(stack)

      lines =
        ["Database Migration Guide for #{stack}:", ""] ++
          Enum.map(guide.steps, &("  " <> &1)) ++
          ["", "Rollback: #{guide.rollback}", "Backup: #{guide.backup_before}"]

      {:ok, lines}
    end
  end

  def run_command(%{command: :deploy_scaling, options: options}, _project_root) do
    with {:ok, stack} <-
           parse_atom_option(options[:stack] || "phoenix", deployment_stacks(), "stack") do
      guide = Advisor.scaling_guide(stack)

      lines = ["Scaling Guide for #{stack}:", ""]

      lines =
        lines ++
          ["Vertical Scaling:", "  #{guide.vertical_scaling.description}"] ++
          Enum.map(guide.vertical_scaling.tiers, fn t ->
            "  #{t.users} users: #{t.tier} - #{t.cost}"
          end) ++
          [
            "",
            "Horizontal: #{guide.horizontal_scaling}",
            "",
            "Database: #{guide.database_scaling}"
          ]

      {:ok, lines}
    end
  end

  def run_command(%{command: :cost_optimize, options: options}, _project_root) do
    session_id = options[:session_id]
    provider = options[:provider]
    model = options[:model]

    spending =
      if session_id do
        import Ecto.Query

        from(i in ControlKeel.Mission.Invocation,
          where: i.session_id == ^session_id,
          select: %{
            estimated_cost_cents: i.estimated_cost_cents,
            tool: i.tool,
            metadata: i.metadata
          }
        )
        |> ControlKeel.Repo.all()
      else
        []
      end

    case CostOptimizer.suggest(session_id || "cli",
           spending: spending,
           top_provider: provider,
           top_model: model
         ) do
      {:ok, []} ->
        {:ok, ["No cost optimization suggestions at this time."]}

      {:ok, suggestions} ->
        lines =
          Enum.map(suggestions, fn s ->
            "[#{s.priority}] #{s.title}\n  #{s.description}\n  Potential savings: #{s.savings_percent}%"
          end)

        {:ok, ["Cost Optimization Suggestions:", "" | lines]}
    end
  end

  def run_command(%{command: :cost_compare, options: options}, _project_root) do
    tokens = options[:tokens] || 10_000

    case CostOptimizer.compare_agents("CLI comparison", estimated_tokens: tokens) do
      {:ok, result} ->
        lines =
          Enum.map(result.comparisons, fn c ->
            "$#{Float.round(c.estimated_cost_usd, 4)}  #{c.agent} (#{c.provider}/#{c.model})"
          end)

        savings =
          if result.savings_range > 0 do
            ["", "Potential savings: $#{Float.round(result.savings_range / 100, 2)}"]
          else
            []
          end

        {:ok, ["Agent cost comparison (#{tokens} tokens):", "" | lines] ++ savings}
    end
  end

  def run_command(%{command: :precommit_check, options: options}, project_root) do
    root = options[:project_root] || project_root
    domain_pack = options[:domain_pack]
    enforce = options[:enforce] || false

    case PreCommitHook.check(root, domain_pack: domain_pack, enforce: enforce) do
      {:ok, result} ->
        staged_count = length(Map.get(result, :staged_files, []))

        case result.decision do
          "allow" ->
            {:ok, ["No policy violations found in #{staged_count} staged file(s)."]}

          "warn" ->
            lines =
              ["#{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:ok, lines}

          "block" ->
            lines =
              ["BLOCKED: #{result.summary}"] ++
                Enum.map(result.findings, fn f ->
                  "  [#{f.severity}] #{f.rule_id}: #{f.plain_message}"
                end)

            {:error, Enum.join(lines, "\n")}
        end
    end
  end

  def run_command(%{command: :precommit_install, options: options}, project_root) do
    root = options[:project_root] || project_root
    enforce = options[:enforce] || false

    case PreCommitHook.install(root, enforce: enforce) do
      {:ok, :installed} ->
        {:ok, ["Pre-commit hook installed in .git/hooks/pre-commit"]}

      {:ok, :updated} ->
        {:ok, ["Pre-commit hook updated in .git/hooks/pre-commit"]}

      {:error, :hook_exists} ->
        {:error, "A non-ControlKeel pre-commit hook already exists. Remove it first."}
    end
  end

  def run_command(%{command: :precommit_uninstall, options: options}, project_root) do
    root = options[:project_root] || project_root

    case PreCommitHook.uninstall(root) do
      {:ok, :uninstalled} ->
        {:ok, ["Pre-commit hook removed."]}

      {:ok, :not_controlkeel_hook} ->
        {:error, "Existing hook is not a ControlKeel hook."}

      {:ok, :no_hook_found} ->
        {:ok, ["No pre-commit hook found."]}
    end
  end

  def run_command(%{command: :progress, options: options}, project_root) do
    session_id = options[:session_id]

    session_id =
      if session_id do
        session_id
      else
        case LocalProject.load(project_root) do
          {:ok, _binding, session} -> session.id
          _ -> nil
        end
      end

    if is_nil(session_id) do
      {:error, "No active session. Use --session-id or run from a bound project."}
    else
      case ControlKeel.Mission.Progress.compute(session_id) do
        {:ok, progress} ->
          with {:ok, format} <- cli_output_format(options) do
            current_task = progress.tasks.current_task

            lines = [
              "Session ##{session_id} Progress: #{progress.overall_percent}%",
              "",
              "Tasks: #{progress.tasks.done}/#{progress.tasks.total} done (#{progress.tasks.in_progress} in progress, #{progress.tasks.blocked} blocked)",
              "Findings: #{progress.findings.resolved}/#{progress.findings.total} resolved (#{progress.findings.critical_open} critical open)",
              "Budget: $#{progress.budget.spent_cents / 100} / $#{progress.budget.budget_cents / 100} (#{progress.budget.percent}%) [#{progress.budget.status}]",
              "Estimated effort: #{progress.estimated_effort.estimated_hours}h (#{progress.estimated_effort.estimated_days} days)",
              "Current task: #{(current_task && current_task.title) || "No task in progress"}"
            ]

            remaining =
              Enum.map(progress.remaining_items, fn item ->
                prefix =
                  case item.type do
                    :blocker -> "BLOCKER"
                    :warning -> "WARN"
                    _ -> "INFO"
                  end

                "  #{prefix}: #{item.message}"
              end)

            lines =
              if remaining != [] do
                lines ++ ["", "Remaining:"] ++ remaining
              else
                lines
              end

            help_lines = progress_help_lines(progress, current_task)

            payload = %{
              "session_id" => session_id,
              "overall_percent" => progress.overall_percent,
              "tasks" => progress.tasks,
              "findings" => progress.findings,
              "budget" => progress.budget,
              "estimated_effort" => progress.estimated_effort,
              "current_task" => current_task_payload(current_task),
              "remaining_items" => progress.remaining_items,
              "suggested_next_steps" => help_lines_to_values(help_lines)
            }

            case format do
              "json" ->
                {:ok, [Jason.encode!(payload)]}

              _ ->
                {:ok, lines ++ help_lines}
            end
          else
            {:error, {:invalid_output_format, message}} ->
              {:error, message}
          end

        {:error, :session_not_found} ->
          {:error, "Session ##{session_id} not found."}
      end
    end
  end

  def run_command(%{command: :findings_translate, options: options}, project_root) do
    session_id = options[:session_id]

    findings =
      if session_id do
        ControlKeel.Mission.list_session_findings(session_id)
      else
        case LocalProject.load(project_root) do
          {:ok, _binding, session} ->
            ControlKeel.Mission.list_session_findings(session.id)

          _ ->
            []
        end
      end

    if findings == [] do
      {:ok, ["No findings to translate."]}
    else
      translated = PlainEnglish.translate_list(findings)

      lines =
        Enum.flat_map(translated, fn t ->
          [""] ++
            ["#{t.rule_id} [#{t.severity}]: #{t.title}"] ++
            ["  #{t.category_explanation}"] ++
            if(t.fix, do: ["  Fix: #{t.fix}"], else: []) ++
            if(t.risk_if_ignored, do: ["  Risk: #{t.risk_if_ignored}"], else: [])
        end)

      {:ok, ["Findings in plain English:", "" | tl(lines)]}
    end
  end

  def run_command(%{command: :circuit_breaker_status, options: options}, _project_root) do
    agent_id = options[:agent_id]

    if agent_id do
      case CircuitBreaker.check_status(agent_id) do
        {:ok, status} ->
          lines = [
            "Agent: #{status.agent_id}",
            "Status: #{status.status}",
            "Events: #{status.event_count} (API: #{status.api_calls}, Files: #{status.file_modifications}, Errors: #{status.errors})"
          ]

          lines =
            if status.trip_reason do
              lines ++ ["Trip reason: #{status.trip_reason}"]
            else
              lines
            end

          {:ok, lines}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    else
      case CircuitBreaker.get_all_statuses() do
        {:ok, statuses} ->
          if statuses == [] do
            {:ok, ["No agents tracked by circuit breaker."]}
          else
            lines =
              Enum.map(statuses, fn s ->
                "#{s.agent_id}: #{s.status} (#{s.event_count} events)"
              end)

            {:ok, ["Circuit Breaker Status:", "" | lines]}
          end
      end
    end
  end

  def run_command(%{command: :circuit_breaker_trip, options: options}, _project_root) do
    agent_id = options[:agent_id]

    case CircuitBreaker.trip_breaker(agent_id, "manual CLI trip") do
      {:ok, _} ->
        {:ok, ["Circuit breaker tripped for agent: #{agent_id}"]}
    end
  end

  def run_command(%{command: :circuit_breaker_reset, options: options}, _project_root) do
    agent_id = options[:agent_id]

    case CircuitBreaker.reset_breaker(agent_id) do
      {:ok, _} ->
        {:ok, ["Circuit breaker reset for agent: #{agent_id}"]}
    end
  end

  def run_command(%{command: :agents_monitor, options: options}, _project_root) do
    agent_id = options[:agent_id]

    if agent_id do
      {:ok, events} = AgentMonitor.get_events(agent_id, limit: 20)

      if events == [] do
        {:ok, ["No events for agent: #{agent_id}"]}
      else
        lines =
          Enum.map(events, fn e ->
            ts = e.timestamp |> DateTime.to_iso8601()
            ts <> " " <> to_string(e.event_type) <> " " <> inspect(e.metadata)
          end)

        {:ok, ["Recent events for #{agent_id}:", "" | lines]}
      end
    else
      {:ok, agents} = AgentMonitor.get_active_agents()

      if agents == [] do
        {:ok, ["No active agents."]}
      else
        lines =
          Enum.map(agents, fn a ->
            "#{a.agent_id}: #{to_string(a.status)} (#{a.recent_events_5min} events in 5min, #{a.total_events} total)"
          end)

        {:ok, ["Active agents:", "" | lines]}
      end
    end
  end

  def run_command(%{command: :outcome_record, args: [session_id, outcome]}, _project_root) do
    with {sid, ""} <- Integer.parse(session_id),
         {:ok, outcome_atom} <-
           parse_atom_option(outcome, OutcomeTracker.valid_outcomes(), "outcome") do
      agent_id = "cli-session-#{sid}"

      case OutcomeTracker.record(sid, outcome_atom, agent_id: agent_id) do
        {:ok, result} ->
          {:ok, ["Recorded #{outcome} for session ##{session_id} (reward: #{result.reward})"]}

        {:error, {:unknown_outcome, o}} ->
          {:error,
           "Unknown outcome: #{o}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}

        {:error, reason} ->
          {:error, "Failed: " <> inspect(reason)}
      end
    else
      :error ->
        {:error, "`session_id` must be an integer"}

      {:error, _reason} ->
        {:error,
         "Unknown outcome: #{outcome}. Valid: #{Enum.join(OutcomeTracker.valid_outcomes(), ", ")}"}
    end
  end

  def run_command(%{command: :outcome_score, args: [agent_id]}, _project_root) do
    case OutcomeTracker.get_agent_score(agent_id) do
      {:ok, score} ->
        {:ok,
         [
           "Agent: #{score.agent_id}",
           "Score: #{score.score} (#{score.outcome_count} outcomes, total reward: #{score.total_reward})",
           "Window: #{score.window_days} days"
         ]}
    end
  end

  def run_command(%{command: :outcome_leaderboard}, _project_root) do
    case OutcomeTracker.get_leaderboard() do
      {:ok, []} ->
        {:ok, ["No outcomes recorded yet."]}

      {:ok, scores} ->
        lines =
          Enum.map(scores, fn s ->
            id = s.agent_id || "unknown"
            id <> ": " <> to_string(s.score) <> " (" <> to_string(s.outcome_count) <> " outcomes)"
          end)

        {:ok, ["Agent Leaderboard:", "" | lines]}
    end
  end

  defp skills_list_payload(root, selected_target, skills, diagnostics) do
    %{
      "project_root" => Path.expand(root),
      "target" => selected_target,
      "skills" => Enum.map(skills, &skill_payload/1),
      "diagnostics" => Enum.map(diagnostics, &skill_diagnostic_payload/1)
    }
  end

  defp skill_payload(skill) do
    %{
      "name" => skill.name,
      "description" => skill.description,
      "path" => skill.path,
      "scope" => skill.scope,
      "compatibility_targets" => skill.compatibility_targets || [],
      "required_mcp_tools" => skill.required_mcp_tools || []
    }
  end

  defp skill_diagnostic_payload(diagnostic) do
    %{
      "level" => diagnostic.level,
      "code" => diagnostic.code,
      "message" => diagnostic.message,
      "path" => diagnostic.path,
      "skill_name" => diagnostic.skill_name
    }
  end

  defp format_skills_list(skills, diagnostics) do
    lines =
      if skills == [] do
        ["No skills available for the selected scope or target."]
      else
        Enum.flat_map(skills, fn skill ->
          targets =
            if skill.compatibility_targets == [],
              do: "mcp",
              else: Enum.join(skill.compatibility_targets, ", ")

          tools =
            if skill.required_mcp_tools == [],
              do: "none",
              else: Enum.join(skill.required_mcp_tools, ", ")

          [
            "#{skill.name} [#{skill.scope}]",
            "  #{skill.description}",
            "  targets: #{targets}",
            "  CK tools: #{tools}"
          ]
        end)
      end

    diagnostic_lines =
      if diagnostics == [] do
        []
      else
        ["", "Diagnostics:"] ++
          Enum.map(diagnostics, fn diagnostic ->
            "  [#{diagnostic.level}] #{diagnostic.code} — #{diagnostic.message}"
          end)
      end

    lines ++ diagnostic_lines
  end

  defp format_token_audit(result, mode, "text") do
    case mode do
      "full" ->
        rule_files = result["rule_files"] || []
        skills = result["skills"] || []
        duplicates = result["skill_duplicates"] || result["duplicates"] || []

        recommendations =
          (result["recommendations"] || []) ++ (result["skill_recommendations"] || [])

        [
          "Token Audit Results",
          "===================",
          "",
          "Project root: #{result["project_root"]}",
          "Total estimated tokens: #{result["estimated_tokens"]}",
          "Rule files: #{length(rule_files)}",
          "Skills: #{length(skills)}",
          "Skill tokens: #{result["total_skill_tokens"] || 0}",
          "Duplicate skill groups: #{length(duplicates)}",
          "Duplicate skill tokens: #{result["duplicate_token_count"] || 0}",
          "",
          "Rule files:"
        ] ++
          Enum.map(rule_files, fn rf -> "  - #{rf["path"]} (#{token_count(rf)} tokens)" end) ++
          [
            "",
            "Skills:"
          ] ++
          Enum.map(skills, fn s -> "  - #{s["name"]} (#{token_count(s)} tokens)" end) ++
          [
            "",
            "Duplicate skill groups:"
          ] ++
          Enum.map(duplicates, &format_skill_duplicate/1) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(recommendations, fn r -> "  - #{r}" end)

      "rules" ->
        rule_files = result["rule_files"] || []

        [
          "Token Audit - Rule Files",
          "=========================",
          "",
          "Project root: #{result["project_root"]}",
          "Total rule tokens: #{result["estimated_tokens"]}",
          "Rule files: #{length(rule_files)}",
          ""
        ] ++
          Enum.map(rule_files, fn rf -> "  - #{rf["path"]} (#{token_count(rf)} tokens)" end)

      "skills" ->
        skills = result["skills"] || []
        duplicates = result["duplicates"] || []

        [
          "Token Audit - Skills",
          "====================",
          "",
          "Project root: #{result["project_root"]}",
          "Total skill tokens: #{result["total_skill_tokens"] || result["estimated_tokens"] || 0}",
          "Duplicate skill tokens: #{result["duplicate_token_count"] || 0}",
          "Skills: #{length(skills)}",
          "Duplicate skill groups: #{length(duplicates)}",
          ""
        ] ++
          Enum.map(skills, fn s -> "  - #{s["name"]} (#{token_count(s)} tokens)" end) ++
          [
            "",
            "Duplicate skill groups:"
          ] ++
          Enum.map(duplicates, &format_skill_duplicate/1) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(result["recommendations"] || [], fn r -> "  - #{r}" end)

      "tools" ->
        tools = result["tools"] || []

        [
          "Token Audit - Tools",
          "===================",
          "",
          "Project root: #{result["project_root"]}",
          "Total tool tokens: #{result["total_tokens"] || result["estimated_tokens"] || 0}",
          "Tools: #{length(tools)}",
          ""
        ] ++
          Enum.map(tools, fn t -> "  - #{t["name"]} (#{token_count(t)} tokens)" end) ++
          [
            "",
            "Recommendations:"
          ] ++
          Enum.map(result["recommendations"] || [], fn r -> "  - #{r}" end)
    end
  end

  defp format_token_audit(result, _mode, "json") do
    [Jason.encode!(result, pretty: true)]
  end

  defp token_count(item) when is_map(item) do
    item["tokens"] || item["estimated_tokens"] || item["total_tokens"] || 0
  end

  defp format_skill_duplicate(%{"name" => name} = duplicate) do
    locations =
      duplicate
      |> Map.get("locations", [])
      |> Enum.join(", ")

    "  - #{name}: #{duplicate["count"] || 0} copies, #{duplicate["total_tokens"] || 0} tokens (#{locations})"
  end

  defp format_skill_duplicate(duplicate) when is_map(duplicate) do
    "  - #{duplicate["path"] || "unknown"} (duplicate of #{duplicate["original"] || "unknown"})"
  end

  defp format_tool_groups_suggest(groups, reason, stats, "text") do
    [
      "Tool Groups Suggestion:",
      "  Suggested groups: #{inspect(groups)}",
      "  Reason: #{reason}",
      "  Usage stats:",
      "    Total calls: #{stats.total_calls}",
      "    Unique tools: #{stats.unique_tools}",
      "",
      "To apply this suggestion to your project, run:",
      "  controlkeel tool groups suggest --apply"
    ]
  end

  defp format_tool_groups_suggest(groups, reason, stats, "json") do
    Jason.encode!(
      %{
        suggested: groups,
        reason: reason,
        usage_stats: stats
      },
      pretty: true
    )
    |> then(&[&1])
  end

  defp deployment_stacks, do: [:phoenix, :react, :rails, :node, :python, :static]
  defp hosting_tiers, do: HostingCost.available_tiers() |> Map.keys()
  defp database_tiers, do: HostingCost.available_database_tiers() |> Map.keys()

  defp parse_atom_option(value, allowed, _field) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid}
  end

  defp parse_atom_option(value, allowed, field) when is_binary(value) do
    trimmed = String.trim(value)

    case Enum.find(allowed, &(to_string(&1) == trimmed)) do
      nil ->
        {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

      atom ->
        {:ok, atom}
    end
  end

  defp parse_atom_option(_value, allowed, field),
    do: {:error, "`#{field}` must be one of #{Enum.join(Enum.map(allowed, &to_string/1), ", ")}"}

  defp watch_loop(session_id, seen, interval) do
    findings = Mission.list_session_findings(session_id)
    session = Mission.get_session(session_id)

    new_findings = Enum.reject(findings, fn f -> MapSet.member?(seen, f.id) end)
    updated_seen = Enum.reduce(new_findings, seen, fn f, acc -> MapSet.put(acc, f.id) end)

    Enum.each(new_findings, fn f ->
      severity_badge =
        case f.severity do
          "critical" -> "[CRITICAL]"
          "high" -> "[HIGH]    "
          "medium" -> "[MEDIUM]  "
          _ -> "[LOW]     "
        end

      status =
        case f.status do
          "blocked" -> "BLOCKED"
          "approved" -> "approved"
          "rejected" -> "rejected"
          "escalated" -> "ESCALATED"
          _ -> "open"
        end

      IO.puts("")
      IO.puts("  #{severity_badge} #{f.rule_id}  (#{status})")
      IO.puts("  #{f.plain_message || f.title}")
    end)

    if session do
      spent = session.spent_cents || 0
      budget = session.budget_cents || 0
      rolling = Budget.rolling_24h_spend_cents(session.id)
      pct = if budget > 0, do: round(spent / budget * 100), else: 0
      filled = round(pct / 5)
      bar = "[" <> String.duplicate("█", filled) <> String.duplicate("░", 20 - filled) <> "]"
      IO.puts("")

      IO.puts(
        "  Budget  #{bar}  #{format_money(spent)}/#{format_money(budget)} (#{pct}%)  | rolling 24h: #{format_money(rolling)}"
      )

      IO.puts(String.duplicate("─", 60))
    end

    Process.sleep(interval)
    watch_loop(session_id, updated_seen, interval)
  end

  defp parse_skills_subcommand(command, [target | rest] = argv, switches)
       when byte_size(target) > 0 do
    case target do
      "-" <> _ -> parse_with_switches(command, argv, switches)
      _ -> parse_with_switches(command, ["--target", target | rest], switches)
    end
  end

  defp parse_skills_subcommand(command, argv, switches) do
    parse_with_switches(command, argv, switches)
  end

  defp parse_obs_run(session_id, rest) do
    parse_obs_session_command(:obs_run, session_id, rest)
  end

  defp parse_obs_session_command(command, session_id, rest) do
    with {id, ""} <- Integer.parse(session_id),
         {:ok, parsed} <- parse_with_switches(command, rest, @obs_switches) do
      {:ok, %{parsed | args: [id]}}
    else
      _ -> {:error, "Invalid session id: #{session_id}"}
    end
  end

  defp parse_obs_benchmark_status(command, draft_id, rest) do
    with {id, ""} <- Integer.parse(draft_id),
         {:ok, parsed} <- parse_with_switches(command, rest, @obs_switches) do
      {:ok, %{parsed | args: [id]}}
    else
      _ -> {:error, "Invalid benchmark draft id: #{draft_id}"}
    end
  end

  defp parse_obs_import(file_path, rest) do
    with {:ok, parsed} <- parse_with_switches(:obs_import, rest, @obs_import_switches) do
      {:ok, %{parsed | args: [file_path]}}
    end
  end

  defp parse_obs_workshop(file_path, rest) do
    with {:ok, parsed} <- parse_with_switches(:obs_workshop, rest, @obs_workshop_switches) do
      {:ok, %{parsed | args: [file_path]}}
    end
  end

  defp parse_obs_timeline([]), do: parse_with_switches(:obs_timeline, [], @obs_switches)

  defp parse_obs_timeline([maybe_session_id | rest]) do
    case Integer.parse(maybe_session_id) do
      {session_id, ""} ->
        with {:ok, parsed} <- parse_with_switches(:obs_timeline, rest, @obs_switches) do
          {:ok, %{parsed | args: [session_id]}}
        end

      _ ->
        parse_with_switches(:obs_timeline, [maybe_session_id | rest], @obs_switches)
    end
  end

  defp parse_obs_memory([]), do: parse_with_switches(:obs_memory, [], @obs_switches)

  defp parse_obs_memory([maybe_session_id | rest]) do
    case Integer.parse(maybe_session_id) do
      {session_id, ""} ->
        with {:ok, parsed} <- parse_with_switches(:obs_memory, rest, @obs_switches) do
          {:ok, %{parsed | args: [session_id]}}
        end

      _ ->
        parse_with_switches(:obs_memory, [maybe_session_id | rest], @obs_switches)
    end
  end

  defp parse_with_switches(command, argv, switches) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: switches)

    cond do
      invalid != [] ->
        {:error, Help.command_parse_error(command, invalid, remainder, argv)}

      remainder != [] ->
        {:error, Help.command_parse_error(command, invalid, remainder, argv)}

      true ->
        {:ok, %{command: command, options: options, args: []}}
    end
  end

  defp parse_attach(agent, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @attach_switches)

    cond do
      invalid != [] ->
        {:error, Help.command_parse_error(:attach, invalid, remainder, argv)}

      remainder != [] ->
        {:error, Help.command_parse_error(:attach, invalid, remainder, argv)}

      true ->
        case validate_attach_scope(agent, options) do
          {:ok, _scope} ->
            {:ok, %{command: :attach, options: options, args: [agent]}}

          {:error, message} ->
            {:error, message}
        end
    end
  end

  defp parse_memory_search(query, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @memory_search_switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: :memory_search, options: options, args: [query]}}
    end
  end

  defp parse_audit_log(session_id, argv) do
    case OptionParser.parse(argv, strict: @audit_log_switches) do
      {options, [], []} ->
        {:ok, %{command: :audit_log, options: options, args: [session_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_benchmark_export(run_id, argv) do
    {options, remainder, invalid} = OptionParser.parse(argv, strict: @benchmark_export_switches)

    cond do
      invalid != [] ->
        {:error, usage_text()}

      remainder != [] ->
        {:error, usage_text()}

      true ->
        {:ok, %{command: :benchmark_export, options: options, args: [run_id]}}
    end
  end

  defp parse_policy_set_apply(workspace_id, policy_set_id, argv) do
    case OptionParser.parse(argv, strict: @policy_set_apply_switches) do
      {options, [], []} ->
        {:ok,
         %{command: :policy_set_apply, options: options, args: [workspace_id, policy_set_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_default(source, argv) do
    case OptionParser.parse(argv, strict: @provider_default_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_default, options: options, args: [source]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_key(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_key_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_key, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_fallback_chain(argv) do
    case OptionParser.parse(argv, strict: []) do
      {_options, providers, []} when providers != [] ->
        {:ok, %{command: :provider_set_fallback_chain, options: %{}, args: providers}}

      _ ->
        {:ok, %{command: :provider_set_fallback_chain, options: %{}, args: []}}
    end
  end

  defp parse_provider_set_base_url(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_base_url_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_base_url, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_provider_set_model(provider, argv) do
    case OptionParser.parse(argv, strict: @provider_set_model_switches) do
      {options, [], []} ->
        {:ok, %{command: :provider_set_model, options: options, args: [provider]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_runtime_export(runtime_id, argv) do
    case OptionParser.parse(argv, strict: @runtime_export_switches) do
      {options, [], []} ->
        {:ok, %{command: :runtime_export, options: options, args: [runtime_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_review_plan_respond(review_id, argv) do
    case OptionParser.parse(argv, strict: @review_plan_respond_switches) do
      {options, [], []} ->
        {:ok, %{command: :review_plan_respond, options: options, args: [review_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_plugin_command(command, plugin, argv) do
    allowed =
      case command do
        :plugin_export -> ~w(codex claude copilot openclaw augment droid)
        :plugin_install -> ~w(codex claude copilot openclaw)
      end

    if plugin in allowed do
      case OptionParser.parse(argv, strict: @plugin_switches) do
        {options, [], []} ->
          {:ok, %{command: command, options: options, args: [plugin]}}

        _ ->
          {:error, usage_text()}
      end
    else
      {:error, usage_text()}
    end
  end

  defp parse_run_command(command, id, argv) do
    case OptionParser.parse(argv, strict: @agent_run_switches) do
      {options, [], []} ->
        {:ok, %{command: command, options: options, args: [id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp parse_task_command(command, task_id, argv, switches) do
    case OptionParser.parse(argv, strict: switches) do
      {options, [], []} ->
        {:ok, %{command: command, options: options, args: [task_id]}}

      _ ->
        {:error, usage_text()}
    end
  end

  defp required_option(options, key, flag) do
    value =
      cond do
        is_list(options) -> Keyword.get(options, key)
        is_map(options) -> Map.get(options, key)
        true -> nil
      end

    case value do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "#{flag} is required."}
    end
  end

  defp governance_opts(options, project_root) do
    [
      session_id: options[:session_id] || binding_session_id(project_root),
      domain_pack: options[:domain_pack],
      project_root: project_root,
      github: github_metadata_from_env()
    ]
  end

  defp release_ready_session_id(options, project_root) do
    case options[:session_id] || binding_session_id(project_root) do
      nil ->
        {:error,
         "Release readiness requires --session-id or an existing project binding in the current repo."}

      session_id ->
        {:ok, session_id}
    end
  end

  defp release_ready_opts(options, project_root) do
    %{
      sha: options[:sha],
      project_root: project_root,
      smoke: %{
        "status" => options[:smoke_status],
        "artifact_source" => options[:artifact_source]
      },
      provenance: %{
        "verified" => Keyword.get(options, :provenance_verified, false),
        "artifact_source" => options[:artifact_source]
      },
      github: github_metadata_from_env()
    }
  end

  defp patch_input(options) do
    cond do
      is_binary(options[:url]) and options[:url] != "" ->
        Governance.review_pr_url(
          options[:url],
          governance_opts(options, options[:project_root] || File.cwd!())
        )

      is_binary(options[:patch]) and options[:patch] != "" ->
        case File.read(options[:patch]) do
          {:ok, patch} -> {:ok, patch}
          {:error, reason} -> {:error, "Failed to read patch file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        {:ok, IO.read(:stdio, :eof)}

      true ->
        {:error, "Provide --url <github-pr>, --patch <file>, or --stdin."}
    end
  end

  defp review_pr_input(options, project_root) do
    root = options[:project_root] || project_root

    case patch_input(Keyword.put(options, :project_root, root)) do
      {:ok, %{} = review} ->
        {:ok, review}

      {:ok, patch} when is_binary(patch) ->
        Governance.review_patch(patch, governance_opts(options, root))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp review_submission_input(options) do
    cond do
      is_binary(options[:body_file]) and options[:body_file] != "" ->
        case File.read(options[:body_file]) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, "Failed to read plan file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        {:ok, IO.read(:stdio, :eof)}

      true ->
        {:error, "Provide --body-file <file> or --stdin."}
    end
  end

  defp review_submission_attrs(options, submission_body, project_root) do
    runtime_context = review_runtime_context_from_env()
    effective_project_root = review_scope_project_root(project_root, runtime_context)

    inferred_scope =
      cond do
        is_integer(options[:task_id]) ->
          %{task_id: options[:task_id], session_id: options[:session_id], source: "explicit"}

        is_integer(options[:session_id]) ->
          %{task_id: nil, session_id: options[:session_id], source: "explicit"}

        true ->
          infer_review_scope(runtime_context, effective_project_root)
      end

    {:ok,
     %{
       "session_id" => options[:session_id] || inferred_scope.session_id,
       "task_id" => options[:task_id] || inferred_scope.task_id,
       "title" => options[:title],
       "review_type" => "plan",
       "submission_body" => submission_body,
       "submitted_by" => options[:submitted_by] || runtime_context["agent_id"] || "cli",
       "metadata" => %{
         "runtime_context" => runtime_context,
         "body_file" => options[:body_file],
         "inferred_scope" => %{
           "task_id" => inferred_scope.task_id,
           "session_id" => inferred_scope.session_id,
           "source" => inferred_scope.source
         },
         "effective_project_root" => effective_project_root
       }
     }}
  end

  defp review_response_attrs(options, decision) do
    %{
      "decision" => decision,
      "feedback_notes" => options[:feedback_notes],
      "reviewed_by" => options[:reviewed_by] || "cli",
      "annotations" => parse_review_annotations(options[:annotations])
    }
  end

  defp infer_review_scope(runtime_context, project_root) do
    runtime_task_id = parse_optional_integer(runtime_context["task_id"])
    runtime_session_id = parse_optional_integer(runtime_context["session_id"])

    cond do
      is_integer(runtime_task_id) ->
        %{task_id: runtime_task_id, session_id: runtime_session_id, source: "runtime_context"}

      is_integer(runtime_session_id) ->
        %{task_id: nil, session_id: runtime_session_id, source: "runtime_context"}

      true ->
        infer_review_scope_from_binding(project_root)
    end
  end

  defp infer_review_scope_from_binding(project_root) do
    resolved_root = ProjectRoot.resolve(project_root)

    case LocalProject.load(resolved_root) do
      {:ok, _binding, session} ->
        task = current_session_task(session)

        %{
          task_id: task && task.id,
          session_id: session.id,
          source: "project_binding"
        }

      _ ->
        %{task_id: nil, session_id: nil, source: "none"}
    end
  end

  defp review_scope_project_root(project_root, runtime_context) do
    runtime_root = Map.get(runtime_context, "project_root")

    candidate =
      cond do
        is_binary(project_root) and project_root != "" -> project_root
        is_binary(runtime_root) and runtime_root != "" -> runtime_root
        true -> File.cwd!()
      end

    ProjectRoot.resolve(candidate)
  end

  defp parse_optional_integer(value) when is_integer(value), do: value

  defp parse_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_optional_integer(_value), do: nil

  defp task_in_current_session(project_root, task_id) do
    with {:ok, _binding, session, _mode} <- ensure_local_project(project_root),
         {:ok, parsed_id} <- parse_id(task_id),
         task when not is_nil(task) <- Mission.get_task(parsed_id),
         true <- task.session_id == session.id || {:error, :wrong_session} do
      {:ok, task}
    else
      {:error, :wrong_session} -> {:error, :wrong_session}
      {:error, :invalid_id} -> {:error, :invalid_id}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp optional_risk_tier(nil), do: {:ok, nil}
  defp optional_risk_tier(""), do: {:ok, nil}

  defp optional_risk_tier(value) when value in ["low", "medium", "high", "critical"],
    do: {:ok, value}

  defp optional_risk_tier(_value),
    do: {:error, "--risk-tier must be one of low, medium, high, critical"}

  defp parse_allowed_agents(nil), do: nil
  defp parse_allowed_agents(""), do: nil

  defp parse_allowed_agents(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_task_execution_mode(nil), do: "local"
  defp normalize_task_execution_mode(""), do: "local"
  defp normalize_task_execution_mode("agent"), do: "local"
  defp normalize_task_execution_mode("human"), do: "local"
  defp normalize_task_execution_mode("runtime"), do: "external"

  defp normalize_task_execution_mode(value) when value in ["local", "cloud", "external"],
    do: value

  defp normalize_task_execution_mode(_value), do: "local"

  defp decode_required_json_list(nil, option), do: {:error, {:missing_option, option}}
  defp decode_required_json_list("", option), do: {:error, {:missing_option, option}}

  defp decode_required_json_list(value, option) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) ->
        {:ok, list}

      {:ok, _other} ->
        {:error, "--#{option} must decode to a JSON array"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "--#{option} must be valid JSON: #{Exception.message(error)}"}
    end
  end

  defp decode_optional_json_map(nil, _option), do: {:ok, %{}}
  defp decode_optional_json_map("", _option), do: {:ok, %{}}

  defp decode_optional_json_map(value, option) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = map} ->
        {:ok, map}

      {:ok, _other} ->
        {:error, "--#{option} must decode to a JSON object"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "--#{option} must be valid JSON: #{Exception.message(error)}"}
    end
  end

  defp parse_review_annotations(nil), do: %{}

  defp parse_review_annotations(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = annotations} -> annotations
      _ -> %{"cli_notes" => value}
    end
  end

  defp required_integer_option(options, key, flag) do
    value =
      cond do
        is_list(options) -> Keyword.get(options, key)
        is_map(options) -> Map.get(options, key)
        true -> nil
      end

    case value do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, "#{flag} is required."}
    end
  end

  defp socket_report_input(options) do
    cond do
      is_binary(options[:report]) and options[:report] != "" ->
        case File.read(options[:report]) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, %{} = payload} ->
                {:ok, payload}

              {:ok, _other} ->
                {:error, "Socket report must decode to a JSON object."}

              {:error, %Jason.DecodeError{} = error} ->
                {:error, "Socket report must be valid JSON: #{Exception.message(error)}"}
            end

          {:error, reason} ->
            {:error, "Failed to read Socket report file: #{inspect(reason)}"}
        end

      Keyword.get(options, :stdin, false) ->
        case Jason.decode(IO.read(:stdio, :eof)) do
          {:ok, %{} = payload} ->
            {:ok, payload}

          {:ok, _other} ->
            {:error, "Socket report must decode to a JSON object."}

          {:error, %Jason.DecodeError{} = error} ->
            {:error, "Socket report must be valid JSON: #{Exception.message(error)}"}
        end

      true ->
        {:error, "Provide --report <file> or --stdin."}
    end
  end

  defp plugin_target("codex"), do: {:ok, "codex-plugin"}
  defp plugin_target("claude"), do: {:ok, "claude-plugin"}
  defp plugin_target("copilot"), do: {:ok, "copilot-plugin"}
  defp plugin_target("openclaw"), do: {:ok, "openclaw-plugin"}
  defp plugin_target("augment"), do: {:ok, "augment-plugin"}
  defp plugin_target("droid"), do: {:ok, "droid-plugin"}
  defp plugin_target(_plugin), do: {:error, :unknown_plugin}

  defp plugin_mcp_hint("hosted"), do: ".mcp.hosted.json"
  defp plugin_mcp_hint(_mode), do: ".mcp.json"

  defp agent_run_opts(options, project_root) do
    []
    |> maybe_put_cli_opt(:project_root, project_root)
    |> maybe_put_cli_opt(:agent, options[:agent])
    |> maybe_put_cli_opt(:mode, options[:mode])
    |> maybe_put_cli_opt(:sandbox, options[:sandbox])
  end

  defp maybe_put_cli_opt(opts, _key, nil), do: opts
  defp maybe_put_cli_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp read_json_config(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{} = config} -> config
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp maybe_cli_line(_label, nil), do: []
  defp maybe_cli_line(label, value), do: ["#{label}: #{value}"]

  defp attached_agent_status_lines(binding) do
    attached_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Enum.sort_by(fn {agent, _attrs} -> agent end)

    case attached_agents do
      [] ->
        []

      rows ->
        [
          "Attached agents:"
          | Enum.map(rows, fn {agent, attrs} ->
              version = attrs["controlkeel_version"] || "unknown"
              "  #{agent} (CK v#{version})"
            end)
        ]
    end
  end

  defp contextual_status_help_lines(_session, task, active_findings, improvement) do
    recommended_next_step =
      if is_map(improvement), do: improvement["recommended_next_step"], else: nil

    help_lines =
      []
      |> maybe_add_help_line(
        active_findings > 0,
        "Next: controlkeel findings --status open"
      )
      |> maybe_add_help_line(maybe_task_proof_hint(task))
      |> maybe_add_help_line(
        true,
        "Loop focus: #{recommended_next_step || "observe and rerun the governed loop"}"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp findings_help_lines(findings, options) do
    help_lines =
      []
      |> maybe_add_help_line(
        findings != [],
        "Next: controlkeel approve <finding_id>"
      )
      |> maybe_add_help_line(
        findings != [] and is_nil(options[:status]),
        "Next: controlkeel findings --status blocked"
      )
      |> maybe_add_help_line(
        findings == [],
        "Next: controlkeel status"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp findings_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("severity", options[:severity])
      |> maybe_add_filter("status", options[:status])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  defp effective_cli_format(options) when is_list(options) do
    if Keyword.get(options, :json) == true do
      {:ok, "json"}
    else
      cli_output_format(options)
    end
  end

  defp effective_cli_format(options) when is_map(options) do
    if Map.get(options, :json) == true or Map.get(options, "json") == true do
      {:ok, "json"}
    else
      cli_output_format(options)
    end
  end

  defp maybe_put_tool_int(map, _key, nil), do: map

  defp maybe_put_tool_int(map, key, id) when is_integer(id), do: Map.put(map, key, id)

  defp maybe_put_tool_string(map, _key, nil), do: map
  defp maybe_put_tool_string(map, _key, ""), do: map

  defp maybe_put_tool_string(map, key, path) when is_binary(path), do: Map.put(map, key, path)

  defp cli_output_format(options) when is_list(options) do
    case options[:format] do
      nil ->
        {:ok, "text"}

      "text" ->
        {:ok, "text"}

      "json" ->
        {:ok, "json"}

      other ->
        {:error, {:invalid_output_format, "Output format must be text or json, got #{other}."}}
    end
  end

  defp cli_output_format(options) when is_map(options) do
    case Map.get(options, :format) || Map.get(options, "format") do
      nil ->
        {:ok, "text"}

      "text" ->
        {:ok, "text"}

      "json" ->
        {:ok, "json"}

      other ->
        {:error, {:invalid_output_format, "Output format must be text or json, got #{other}."}}
    end
  end

  defp cli_output_format(_options), do: {:ok, "text"}

  defp observability_loop_status_lines(loop) do
    [
      "Observability learning loop: #{loop.health}",
      "Mode: #{loop.learning_loop.mode}",
      "Read-only: #{loop.read_only} | Mutation: #{loop.mutation}",
      "Automatic benchmark execution: #{loop.learning_loop.automatic_benchmark_execution}",
      "Automatic promotion: #{loop.learning_loop.automatic_promotion}",
      "Problems: #{loop.active_problems.count} group(s) / #{loop.active_problems.total_findings} finding(s)",
      "Evals: #{loop.evals.derived} derived / #{loop.evals.saved} saved",
      "Benchmarks: #{loop.benchmarks.drafts} draft(s), #{loop.benchmarks.scenarios} scenario(s), readiness #{loop.benchmarks.history_readiness.status}",
      "Promotions: #{loop.promotions.count} candidate(s), readiness #{format_frequency(loop.promotions.by_readiness)}",
      "Blockers:"
    ] ++
      Enum.map(loop.blockers, &"- #{&1.id}: #{&1.reason}") ++
      ["Next actions:"] ++
      Enum.map(loop.next_actions, fn action ->
        "- [#{action.priority}] #{action.title}: #{action.suggested_action}"
      end) ++
      ["Recommendations:"] ++ Enum.map(loop.recommendations, &"- #{&1}")
  end

  defp observability_problem_lines(problems) do
    [
      "Observability problems: #{problems.count} grouped / #{problems.total_findings} active finding(s)",
      "Health: #{problems.health}",
      "Recommendations:"
    ] ++
      Enum.map(problems.recommendations, &"- #{&1}") ++
      Enum.flat_map(problems.problems, fn problem ->
        [
          "",
          "[#{problem.health}] #{problem.rule_id} (#{problem.category})",
          "  Severity: #{problem.severity} | Count: #{problem.count} | Sessions: #{problem.affected_session_count}",
          "  Last seen: #{problem.last_seen || "unknown"}",
          "  Next: #{problem.recommendation}",
          "  Feedback loop: #{problem.feedback_loop.eval_candidate_title}",
          "  Eval action: #{problem.feedback_loop.suggested_action}",
          "  Benchmark hint: #{problem.feedback_loop.benchmark_hint}",
          "  Human gate required: #{problem.feedback_loop.human_gate_required}"
        ]
      end)
  end

  defp observability_export_lines(envelope) do
    session = envelope.session_run.session
    integrity = envelope.integrity

    [
      "Observability export preview: #{session.title} (##{session.id})",
      "Schema: #{envelope.schema_version}",
      "Exported at: #{envelope.exported_at}",
      "Health: #{integrity.health}",
      "Timeline events: #{integrity.timeline_events}",
      "Active findings: #{integrity.active_findings}",
      "Problem groups: #{integrity.problem_groups}",
      "Redaction: #{envelope.redaction.policy} (raw context/memory/tool inputs excluded)",
      "Integrity: import mutation allowed = #{integrity.import_mutation_allowed}",
      "Use --format json to write a portable envelope."
    ]
  end

  defp observability_import(file_path, options, project_root) do
    cond do
      options[:persist] == true ->
        ObservabilityTelemetry.import_persist(file_path, observability_import_opts(project_root))

      options[:dry_run] == true ->
        ObservabilityTelemetry.import_preview(file_path, dry_run: true)

      true ->
        {:error, :dry_run_required}
    end
  end

  defp observability_import_opts(project_root) do
    case ensure_local_project(project_root) do
      {:ok, _binding, session, _mode} ->
        [workspace_id: session.workspace_id, session_id: session.id]

      _other ->
        []
    end
  end

  defp observability_workshop_preview(file_path, options) do
    if options[:dry_run] == true do
      ObservabilityWorkshop.preview_file(file_path)
    else
      {:error, :dry_run_required}
    end
  end

  defp observability_workshop_lines(preview) do
    counts = preview.counts
    integrity = preview.integrity

    [
      "Workshop observability dry-run:",
      "Schema: #{preview.schema_version}",
      "Runs: #{counts.runs}",
      "Spans: #{counts.spans} (tools #{counts.tool_spans}, errors #{counts.error_spans})",
      "Live events: #{counts.live_events}",
      "Saved events: #{counts.saved_events}",
      "Redaction: #{preview.redaction.policy} (raw span and event payloads excluded)",
      "Payload chars redacted: #{counts.payload_chars_redacted}",
      "Integrity: #{integrity.payload_sha256}",
      "Mutation: #{preview.mutation}"
    ] ++ Enum.map(preview.recommendations, &"- #{&1}")
  end

  defp observability_import_lines(%{dry_run: true} = preview) do
    [
      "Observability import dry-run:",
      "Schema: #{preview.schema_version}",
      "Exported at: #{preview.exported_at}",
      "Session: #{preview.session_title || "unknown"} (##{preview.session_id || "unknown"})",
      "Health: #{preview.health || "unknown"}",
      "Problem groups: #{preview.problem_groups}",
      "Total problem findings: #{preview.total_problem_findings}",
      "Redaction: #{preview.redaction_policy || "unknown"}",
      "Integrity: #{preview.integrity_status || "unknown"}",
      "Mutation: #{preview.mutation}"
    ]
  end

  defp observability_import_lines(result) do
    [
      "Observability import persisted:",
      "Status: #{result.status}",
      "Record: ##{result.id}",
      "Schema: #{result.schema_version}",
      "Exported at: #{result.exported_at}",
      "Imported at: #{result.imported_at}",
      "Session: #{result.session_title || "unknown"} (##{result.session_id || "unknown"})",
      "Health: #{result.health || "unknown"}",
      "Problem groups: #{result.problem_groups}",
      "Total problem findings: #{result.total_problem_findings}",
      "Redaction: #{result.redaction_policy || "unknown"}",
      "Integrity: #{result.integrity_status || "unknown"}",
      "Mutation: #{result.mutation}"
    ]
  end

  defp observability_memory_quality_lines(quality) do
    totals = quality.totals

    [
      "Observability memory quality: #{totals.records} record(s)",
      "Active: #{totals.active} / Archived: #{totals.archived}",
      "Stale candidates: #{totals.stale_candidates} (threshold #{quality.stale_days} day(s))",
      "Duplicate clusters: #{totals.duplicate_clusters}",
      "Contradiction candidates: #{totals.contradiction_candidates}",
      "Missed-memory sessions: #{totals.missed_memory_sessions}",
      "Types: #{format_frequency(quality.distributions.by_type)}",
      "Sources: #{format_frequency(quality.distributions.by_source)}",
      "Recommendations:"
    ] ++
      Enum.map(quality.recommendations, &"- #{&1}") ++
      ["Stale memory:"] ++
      Enum.map(quality.stale_candidates, fn record ->
        "- ##{record.id} #{record.title} (#{record.age_days || 0} day(s), #{record.record_type})"
      end) ++
      ["Duplicate clusters:"] ++
      Enum.map(quality.duplicate_clusters, fn cluster ->
        "- #{cluster.key}: #{cluster.count} record(s)"
      end) ++
      ["Missed-memory sessions:"] ++
      Enum.map(quality.missed_memory_sessions, fn session ->
        "- ##{session.id} #{session.title}: #{session.findings} finding(s), #{session.reviews} review(s), #{session.invocations} invocation(s)"
      end)
  end

  defp observability_trend_lines(trends) do
    totals = trends.totals

    [
      "Observability trends: #{trends.start_date} to #{trends.end_date} (#{trends.days} day(s))",
      "Runs: #{totals.runs} total (#{totals.red_runs} red / #{totals.yellow_runs} yellow / #{totals.green_runs} green)",
      "Findings: #{totals.active_findings} active / #{totals.blocked_findings} blocked",
      "Estimated spend: #{format_money(totals.estimated_cost_cents)}",
      "Imports: #{totals.imports} persisted (#{totals.verified_imports} verified / #{totals.non_verified_imports} non-verified)",
      "Daily series:"
    ] ++
      Enum.map(trends.series, fn day ->
        "- #{day.date}: #{day.runs} run(s), red #{day.health.red}, yellow #{day.health.yellow}, green #{day.health.green}, findings #{day.active_findings}/#{day.blocked_findings} blocked, cost #{format_money(day.estimated_cost_cents)}, imports #{day.imports}"
      end) ++
      ["Recommendations:"] ++ Enum.map(trends.recommendations, &"- #{&1}")
  end

  defp observability_import_list_lines(imports) do
    [
      "Observability imports: #{imports.count} persisted snapshot(s)",
      "Integrity: #{format_frequency(imports.by_integrity)}",
      "Health: #{format_frequency(imports.by_health)}",
      "Recent imports:"
    ] ++
      Enum.map(imports.recent, fn imported ->
        "- ##{imported.id} #{imported.original_session_title || "unknown"} (session ##{imported.original_session_id || "unknown"}): #{imported.health}, #{imported.problem_groups} problem group(s), integrity #{imported.integrity_status}, hash #{imported.payload_fingerprint || "unknown"}"
      end) ++
      ["Recommendations:"] ++ Enum.map(imports.recommendations, &"- #{&1}")
  end

  defp observability_cost_lines(costs) do
    totals = costs.totals

    [
      "Observability costs: #{totals.invocations} invocation(s) across #{totals.sessions} session(s)",
      "Estimated spend: #{format_money(totals.estimated_cost_cents)}",
      "Tokens: #{totals.input_tokens} input / #{totals.cached_input_tokens} cached / #{totals.output_tokens} output",
      "Grouped by: #{costs.by}",
      "Groups:"
    ] ++
      Enum.map(costs.groups, fn group ->
        "- #{group.name}: #{group.invocations} call(s), #{format_money(group.estimated_cost_cents)}, #{group.input_tokens} input, #{group.output_tokens} output"
      end) ++
      ["Recommendations:"] ++ Enum.map(costs.recommendations, &"- #{&1}")
  end

  defp observability_recommendation_lines(recommendations) do
    [
      "Observability recommendations: #{recommendations.count} action(s)",
      "Health: #{recommendations.health}",
      "Categories: #{Enum.join(recommendations.categories, ", ")}"
    ] ++
      Enum.flat_map(recommendations.actions, fn action ->
        [
          "",
          "[#{action.priority}] #{action.title}",
          "  Category: #{action.category} | Source: #{action.source}",
          "  Evidence: #{action.evidence}",
          "  Next: #{action.suggested_action}",
          "  Link: #{action.link}",
          "  Human gate required: #{action.human_gate_required}"
        ]
      end)
  end

  defp observability_eval_candidate_lines(eval_candidates) do
    [
      "Observability eval candidates: #{eval_candidates.count} candidate(s)",
      "Health: #{eval_candidates.health}",
      "Recommendations:"
    ] ++
      Enum.map(eval_candidates.recommendations, &"- #{&1}") ++
      Enum.flat_map(eval_candidates.candidates, fn candidate ->
        [
          "",
          "[#{candidate.priority}] #{candidate.title}",
          "  Rule: #{candidate.rule_id} | Category: #{candidate.category} | Severity: #{candidate.severity}",
          "  Evidence: #{candidate.evidence_summary}",
          "  Benchmark hint: #{candidate.benchmark_hint}",
          "  Example session: #{candidate.example_session_id || "unknown"}",
          "  Human gate required: #{candidate.human_gate_required}"
        ]
      end)
  end

  defp observability_eval_save_lines(result) do
    [
      "Observability eval candidates saved:",
      "Source candidates: #{result.source_count}",
      "Stored: #{result.stored}",
      "Existing: #{result.existing}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.candidates, fn candidate ->
        "- ##{candidate.id} [#{candidate.priority}] #{candidate.title} (#{candidate.status})"
      end)
  end

  defp observability_saved_eval_lines(saved) do
    [
      "Saved observability eval candidates: #{saved.count}",
      "Status: #{format_frequency(saved.by_status)}",
      "Priority: #{format_frequency(saved.by_priority)}",
      "Recommendations:"
    ] ++
      Enum.map(saved.recommendations, &"- #{&1}") ++
      ["Candidates:"] ++
      Enum.map(saved.candidates, fn candidate ->
        "- ##{candidate.id} [#{candidate.priority}/#{candidate.status}] #{candidate.title}: #{candidate.evidence_summary}"
      end)
  end

  defp observability_benchmark_draft_result_lines(result) do
    [
      "Observability benchmark drafts generated:",
      "Source candidates: #{result.source_count}",
      "Stored: #{result.stored}",
      "Existing: #{result.existing}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.drafts, fn draft ->
        "- ##{draft.id} [#{draft.status}] #{draft.title} (#{draft.suite_slug})"
      end)
  end

  defp observability_benchmark_draft_lines(drafts) do
    [
      "Observability benchmark drafts: #{drafts.count}",
      "Status: #{format_frequency(drafts.by_status)}",
      "Suites: #{format_frequency(drafts.by_suite)}",
      "Recommendations:"
    ] ++
      Enum.map(drafts.recommendations, &"- #{&1}") ++
      ["Drafts:"] ++
      Enum.map(drafts.drafts, fn draft ->
        "- ##{draft.id} [#{draft.status}] #{draft.title}: #{draft.expected_behavior}"
      end)
  end

  defp benchmark_status_for_command(:obs_benchmark_approve), do: "approved"
  defp benchmark_status_for_command(:obs_benchmark_reject), do: "rejected"
  defp benchmark_status_for_command(:obs_benchmark_archive), do: "archived"

  defp observability_promotion_lines(promotions) do
    [
      "Observability promotion candidates: #{promotions.count}",
      "Promotion execution: #{promotions.promotion_execution}",
      "Readiness: #{format_frequency(promotions.by_readiness)}",
      "Recommendations:"
    ] ++
      Enum.map(promotions.recommendations, &"- #{&1}") ++
      ["Candidates:"] ++
      Enum.map(promotions.candidates, fn candidate ->
        "- ##{candidate.id} #{candidate.rule_id}: #{candidate.readiness} — #{candidate.suggested_action}"
      end)
  end

  defp observability_benchmark_history_lines(history) do
    latest = history.latest_run

    [
      "Observability benchmark history:",
      "Readiness: #{history.readiness.status} — #{history.readiness.reason}",
      "Saved eval candidates: #{history.coverage.saved_eval_candidates}",
      "Benchmark drafts: #{history.coverage.benchmark_drafts}",
      "Approved drafts: #{history.coverage.approved_drafts}",
      "Materialized scenarios: #{history.coverage.materialized_scenarios}",
      "Covered scenarios: #{history.coverage.covered_scenarios}",
      "Benchmark runs: #{history.coverage.benchmark_runs}",
      "Latest run: #{if latest, do: "##{latest.id} #{latest.status} catch #{latest.catch_rate}%", else: "none"}",
      "Recommendations:"
    ] ++
      Enum.map(history.recommendations, &"- #{&1}") ++
      ["Recent runs:"] ++
      Enum.map(history.runs, fn run ->
        "- ##{run.id} #{run.suite}: #{run.status}, catch #{run.catch_rate}%, rule-hit #{run.expected_rule_hit_rate}%"
      end)
  end

  defp observability_benchmark_dry_run?(options) do
    if Map.has_key?(options, :dry_run),
      do: options[:dry_run] == true,
      else: options[:execute] != true
  end

  defp observability_benchmark_run_options(options, workspace_id) do
    [
      workspace_id: workspace_id,
      suite: options[:suite],
      subjects: options[:subjects],
      baseline_subject: options[:baseline_subject],
      scenario_slugs: options[:scenario_slugs],
      dry_run: observability_benchmark_dry_run?(options),
      execute: options[:execute] == true
    ]
  end

  defp observability_benchmark_run_lines(%{benchmark_execution: true} = result) do
    [
      "Observability benchmark run ##{result.run_id} completed.",
      "Suite: #{result.suite}",
      "Subjects: #{Enum.join(result.subjects, ", ")}",
      "Status: #{result.status}",
      "Total scenarios: #{result.total_scenarios}",
      "Catch rate: #{result.catch_rate}%",
      "Block rate: #{result.block_rate}%",
      "Expected rule hit rate: #{result.expected_rule_hit_rate}%",
      "Mutation: #{result.mutation}"
    ]
  end

  defp observability_benchmark_run_lines(preview) do
    [
      "Observability benchmark run preview:",
      "Suite: #{preview.suite || "choose one"}",
      "Available suites: #{Enum.join(preview.suites, ", ")}",
      "Subjects: #{preview.subjects || "<required>"}",
      "Scenarios: #{Enum.join(preview.scenario_slugs, ", ")}",
      "Executable: #{preview.executable}",
      "Benchmark execution: #{preview.benchmark_execution}",
      "Command: #{preview.command || "materialize scenarios first"}",
      "Recommendations:"
    ] ++ Enum.map(preview.recommendations, &"- #{&1}")
  end

  defp observability_benchmark_materialize_lines(result) do
    [
      "Observability benchmark scenarios materialized:",
      "Source drafts: #{result.source_count}",
      "Materialized: #{result.materialized}",
      "Existing: #{result.existing}",
      "Benchmark execution: #{result.benchmark_execution}",
      "Mutation: #{result.mutation}"
    ] ++
      Enum.map(result.scenarios, fn scenario ->
        "- ##{scenario.id} #{scenario.name} (#{scenario.suite_slug}/#{scenario.slug})"
      end)
  end

  defp observability_benchmark_scenario_lines(scenarios) do
    [
      "Observability benchmark scenarios: #{scenarios.count}",
      "Suites: #{format_frequency(scenarios.by_suite)}",
      "Recommendations:"
    ] ++
      Enum.map(scenarios.recommendations, &"- #{&1}") ++
      ["Scenarios:"] ++
      Enum.map(scenarios.scenarios, fn scenario ->
        "- ##{scenario.id} #{scenario.name}: #{Enum.join(scenario.expected_rules, ", ")}"
      end)
  end

  defp observability_benchmark_status_lines(result) do
    draft = result.draft

    [
      "Observability benchmark draft updated:",
      "Draft: ##{draft.id} #{draft.title}",
      "Status: #{result.status}",
      "Human gate required: #{result.human_gate_required}",
      "Mutation: #{result.mutation}"
    ]
  end

  defp observability_regression_lines(regressions) do
    [
      "Observability regressions: #{regressions.health.status}",
      "Window: #{regressions.days} day(s)",
      "Reason: #{regressions.health.reason}",
      "Benchmark runs: #{regressions.benchmark_runs.count}",
      "Average catch rate: #{Float.round(regressions.benchmark_runs.average_catch_rate || 0.0, 3)}",
      "Run status: #{format_frequency(regressions.benchmark_runs.by_status)}",
      "Run suites: #{format_frequency(regressions.benchmark_runs.by_suite)}",
      "Saved eval candidates: #{regressions.draft_coverage.saved_eval_candidates}",
      "Benchmark drafts: #{regressions.draft_coverage.benchmark_drafts}",
      "Recommendations:"
    ] ++
      Enum.map(regressions.recommendations, &"- #{&1}") ++
      ["Recent runs:"] ++
      Enum.map(regressions.benchmark_runs.recent, fn run ->
        "- ##{run.id} #{run.suite} #{run.status}: catch #{Float.round(run.catch_rate || 0.0, 3)} (#{run.caught_count}/#{run.total_scenarios})"
      end)
  end

  defp observability_comparison_lines(comparison) do
    [
      "Observability comparison by #{comparison.by}: #{comparison.totals.invocations} invocation(s)",
      "Estimated spend: #{format_money(comparison.totals.estimated_cost_cents)}",
      "Groups:"
    ] ++
      Enum.map(comparison.groups, fn group ->
        "- #{group.name}: #{group.invocations} call(s), #{format_money(group.estimated_cost_cents)}, #{group.cost_per_call_cents} cent(s)/call, #{group.tokens_per_call} token(s)/call, decisions #{inspect(group.decisions)}"
      end) ++
      ["Recommendations:"] ++ Enum.map(comparison.recommendations, &"- #{&1}")
  end

  defp render_engineer_mirror(%{"error" => msg}), do: "Error: #{msg}"

  defp render_engineer_mirror(%{} = m) do
    today = Map.get(m, "today", %{})
    rolling = Map.get(m, "rolling_30d", %{})
    patterns = Map.get(m, "review_patterns")

    rate =
      case Map.get(rolling, "first_pass_rate") do
        nil -> "n/a"
        v when is_float(v) -> "#{trunc(v * 100)}%"
        _ -> "n/a"
      end

    median_depth =
      case Map.get(rolling, "median_refinement_depth") do
        nil -> "n/a"
        v -> "#{v}"
      end

    breakdown =
      rolling
      |> Map.get("outcome_breakdown", %{})
      |> Enum.map(fn {k, v} -> "  #{k}: #{v}" end)
      |> Enum.join("\n")

    patterns_section =
      case patterns do
        nil ->
          ""

        p ->
          [
            "",
            "Learned review patterns:",
            "  median_refinement_depth: #{Map.get(p, "median_refinement_depth") || "n/a"}",
            "  avg_approved_body_length: #{Map.get(p, "avg_approved_body_length") || "n/a"}",
            "  sample_size: #{Map.get(p, "sample_size", 0)}"
          ]
          |> Enum.join("\n")
      end

    """
    You — session ##{Map.get(m, "session_id")}

    Today
      plans submitted:        #{Map.get(today, "plans_submitted", 0)}
      first-pass approvals:   #{Map.get(today, "first_pass_approvals", 0)}
      denials:                #{Map.get(today, "denials", 0)}

    Rolling 30 days
      first-pass rate:        #{rate}
      median refinement depth: #{median_depth}
      prompt outcomes:
    #{if breakdown == "", do: "  (none yet)", else: breakdown}
    #{patterns_section}

    Top signal
      #{Map.get(m, "top_signal") || "(none — keep steering)"}

    Suggestion
      #{Map.get(m, "one_suggestion") || "(nothing to flag right now)"}
    """
  end

  defp render_observability_timeline(session_id, limit, format) do
    case Observability.timeline(session_id, limit: limit) do
      {:ok, timeline} ->
        case format do
          "json" -> {:ok, [Jason.encode!(timeline)]}
          _ -> {:ok, observability_timeline_lines(timeline)}
        end

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  defp observability_timeline_lines(timeline) do
    [
      "Observability timeline: #{timeline.session.title} (##{timeline.session.id})",
      "Events: #{timeline.count} recent / limit #{timeline.limit}",
      "Event types: #{format_frequency(timeline.by_event_type)}",
      "Actors: #{format_frequency(timeline.by_actor)}",
      "Timeline:"
    ] ++
      Enum.map(timeline.events, fn event ->
        "- #{event.inserted_at || "unknown time"} #{event.event_type} by #{event.actor}: #{event.summary}"
      end)
  end

  defp render_observability_memory(session_id, limit, format) do
    case Observability.memory_context(session_id, limit: limit) do
      {:ok, memory_context} ->
        case format do
          "json" -> {:ok, [Jason.encode!(memory_context)]}
          _ -> {:ok, observability_memory_lines(memory_context)}
        end

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  defp observability_memory_lines(memory_context) do
    memory = memory_context.memory
    context = memory_context.context

    [
      "Observability memory: #{memory_context.session.title} (##{memory_context.session.id})",
      "Context: #{context.tasks} task(s), #{context.findings} finding(s), #{context.reviews} review(s), #{context.invocations} invocation(s)",
      "Memory: #{memory.active} active / #{memory.archived} archived / #{memory.count} recent",
      "Types: #{format_frequency(memory.by_type)}",
      "Sources: #{format_frequency(memory.by_source)}",
      "Recent memory:"
    ] ++
      Enum.map(memory.recent, fn record ->
        archived = if record.archived, do: "archived", else: "active"
        "- [#{record.record_type}] #{record.title} (#{archived}) — #{record.summary}"
      end) ++
      ["Recommendations:"] ++ Enum.map(memory_context.recommendations, &"- #{&1}")
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp render_observability(session_id, format) do
    case Observability.session_run(session_id) do
      {:ok, run} ->
        case format do
          "json" -> {:ok, [Jason.encode!(run)]}
          _ -> {:ok, observability_lines(run)}
        end

      {:error, :not_found} ->
        {:error, "Session not found: #{session_id}"}

      {:error, :invalid_session_id} ->
        {:error, "Invalid session id: #{session_id}"}
    end
  end

  defp observability_lines(run) do
    session = run.session
    health = run.health
    budget = run.budget
    findings = run.findings
    tasks = run.tasks
    gates = run.gates
    timeline = run.timeline
    memory = run.memory
    proofs = run.proofs
    host_metrics = run.hosts_models_tools

    [
      "Observability: #{session.title} (##{session.id})",
      "Health: #{health.status} — #{health.label}",
      "Reasons: #{Enum.join(health.reasons, "; ")}",
      "Budget: #{format_money(budget["spent_cents"] || 0)} / #{format_money(budget["session_budget_cents"] || 0)} used (#{budget["decision"] || "unknown"})",
      "Findings: #{findings.active} active / #{findings.total} total (#{findings.critical} critical, #{findings.high} high, #{findings.blocked} blocked)",
      "Tasks: #{tasks.active} active / #{tasks.total} total",
      "Gates: #{gates.pending_reviews} pending review(s) / #{gates.total_reviews} total",
      "Timeline: #{timeline.count} recent event(s)",
      "Memory: #{memory.records} active record(s)",
      "Proof bundles: #{proofs.count}",
      "Invocations: #{host_metrics.invocations} call(s), #{format_money(host_metrics.estimated_cost_cents)} estimated",
      "Recommendations:"
    ] ++ Enum.map(run.recommendations, &"- #{&1}")
  end

  defp proofs_filter_summary(options) do
    filters =
      []
      |> maybe_add_filter("task_id", options[:task_id])
      |> maybe_add_filter("deploy_ready", options[:deploy_ready])

    case filters do
      [] -> ""
      values -> " (" <> Enum.join(values, ", ") <> ")"
    end
  end

  defp benchmark_filter_summary(options) do
    case options[:domain_pack] do
      nil -> ""
      "" -> ""
      domain_pack -> " (domain_pack=#{domain_pack})"
    end
  end

  defp maybe_add_filter(filters, _label, nil), do: filters
  defp maybe_add_filter(filters, _label, ""), do: filters
  defp maybe_add_filter(filters, label, value), do: filters ++ ["#{label}=#{value}"]

  defp current_session_task(session) do
    Enum.find(session.tasks, &(&1.status == "in_progress")) ||
      Enum.find(session.tasks, &(&1.status == "queued")) ||
      List.first(session.tasks)
  end

  defp current_task_payload(nil), do: nil

  defp current_task_payload(task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "status" => task.status
    }
  end

  defp proofs_help_lines(proofs, options) do
    help_lines =
      []
      |> maybe_add_help_line(
        proofs != [],
        "Next: controlkeel proof <proof_id>"
      )
      |> maybe_add_help_line(
        proofs != [] and is_nil(options[:deploy_ready]),
        "Next: controlkeel proofs --deploy-ready true"
      )
      |> maybe_add_help_line(
        proofs == [],
        "Next: controlkeel status"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp progress_help_lines(progress, current_task) do
    help_lines =
      []
      |> maybe_add_help_line(
        progress.findings.critical_open > 0 or progress.findings.blocked > 0,
        "Next: controlkeel findings --status blocked"
      )
      |> maybe_add_help_line(maybe_task_proof_hint(current_task))
      |> maybe_add_help_line(
        progress.tasks.queued > 0,
        "Next: controlkeel run task <task_id>"
      )

    case help_lines do
      [] -> []
      lines -> ["", "Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp benchmark_list_help_lines(suites, runs, subjects) do
    help_lines =
      []
      |> maybe_add_help_line(
        suites != [],
        "Next: controlkeel benchmark run --suite <suite_slug> --subjects <subject_ids>"
      )
      |> maybe_add_help_line(
        runs != [],
        "Next: controlkeel benchmark show <run_id>"
      )
      |> maybe_add_help_line(
        subjects == [],
        "Next: controlkeel benchmark import <run_id> <subject> <file>"
      )

    case help_lines do
      [] -> []
      lines -> ["", "Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp benchmark_show_help_lines(run) do
    help_lines =
      []
      |> maybe_add_help_line(
        true,
        "Next: controlkeel benchmark export #{run.id} --format csv"
      )
      |> maybe_add_help_line(
        run.status != "completed",
        "Next: controlkeel benchmark import #{run.id} <subject> <file>"
      )

    case help_lines do
      [] -> []
      lines -> ["Suggested next steps:" | Enum.map(lines, &"  #{&1}")]
    end
  end

  defp session_workspace_context(session, project_root) do
    session
    |> WorkspaceContext.resolve_project_root(project_root)
    |> case do
      nil -> ProjectRoot.resolve(project_root)
      resolved -> resolved
    end
    |> WorkspaceContext.build()
  end

  defp augmentation_status_line(%{"available" => true} = augmentation) do
    likely_paths = augmentation["likely_paths"] |> List.wrap() |> Enum.take(3)
    search_terms = augmentation["search_terms"] |> List.wrap() |> Enum.take(3)

    summary =
      [
        truncate_cli(augmentation["objective"], 90),
        list_hint("paths", likely_paths),
        list_hint("terms", search_terms)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")

    if summary == "", do: "available", else: summary
  end

  defp augmentation_status_line(_augmentation), do: "not available yet"

  defp security_case_status_line(%{"case_count" => 0}), do: "0 tracked"

  defp security_case_status_line(%{"case_count" => case_count} = summary) do
    unresolved = summary["unresolved"] || 0
    critical = summary["critical_unresolved"] || 0

    "#{case_count} tracked | #{unresolved} unresolved | #{critical} critical unresolved"
  end

  defp security_case_status_line(_summary), do: "not recorded"

  defp list_hint(_label, []), do: nil
  defp list_hint(label, values), do: "#{label}: #{Enum.join(values, ", ")}"

  defp truncate_cli(nil, _limit), do: nil

  defp truncate_cli(text, limit) when is_binary(text) and byte_size(text) > limit do
    "#{binary_part(text, 0, limit)}... (#{byte_size(text)} chars)"
  end

  defp truncate_cli(text, _limit), do: text

  defp attached_agent_status_payload(binding) do
    binding
    |> Map.get("attached_agents", %{})
    |> Enum.sort_by(fn {agent, _attrs} -> agent end)
    |> Enum.map(fn {agent, attrs} ->
      %{
        "agent" => agent,
        "controlkeel_version" => attrs["controlkeel_version"] || "unknown"
      }
    end)
  end

  defp help_lines_to_values(lines) do
    lines
    |> Enum.reject(&(&1 == "Suggested next steps:" or &1 == ""))
    |> Enum.map(&String.trim/1)
  end

  defp maybe_add_help_line(lines, true, line), do: lines ++ [line]
  defp maybe_add_help_line(lines, false, _line), do: lines
  defp maybe_add_help_line(lines, nil), do: lines
  defp maybe_add_help_line(lines, line) when is_binary(line), do: lines ++ [line]

  defp maybe_task_proof_hint(%{id: id}), do: "Next: controlkeel proofs --task-id #{id}"
  defp maybe_task_proof_hint(_task), do: nil

  defp agent_execution_lines(result) do
    [
      "Delegated task ##{result["task_id"]}.",
      "Agent: #{result["agent_id"]}",
      "Mode: #{result["mode"]}",
      "Status: #{result["status"]}",
      "Run package: #{result["package_root"]}"
    ] ++
      maybe_cli_line("OAuth client id", result["oauth_client_id"]) ++
      maybe_cli_line("Client secret", result["client_secret"]) ++
      maybe_cli_line("Bundle path", result["bundle_path"])
  end

  defp format_cli_error({:invalid_arguments, reason}), do: reason
  defp format_cli_error({:policy_blocked, reason}), do: reason
  defp format_cli_error(:not_found), do: "not found"
  defp format_cli_error(:invalid_id), do: "invalid id"

  defp format_cli_error({:review_denied, review}),
    do: "Plan review was denied." <> format_review_feedback_error(review)

  defp format_cli_error({:review_pending, details}),
    do:
      "Task is waiting on plan approval (review ##{details[:review_id] || "unknown"}, status #{details[:review_status] || "pending"})."

  defp format_cli_error({:execution_not_ready, details}),
    do:
      "Plan is approved (review ##{details[:review_id] || "unknown"}) but execution is not ready. Refine the plan to reach execution-ready phase, or approve a deeper plan phase."

  defp format_cli_error({:timeout, review}),
    do: "Timed out waiting for plan review ##{review.id}." <> format_review_feedback_error(review)

  defp format_cli_error(reason), do: inspect(reason)

  defp review_url(review_id), do: Endpoint.url() <> "/reviews/#{review_id}"

  defp manual_approval_lines(review, %{server_serving: false}) do
    [
      "Manual approval fallback: review server is not reachable from this CLI session.",
      "Approve from CLI after explicit human approval: controlkeel review plan respond --id #{review.id} --decision approved --feedback-notes \"User approved in chat; review server unavailable\""
    ]
  end

  defp manual_approval_lines(_review, %{opened: false}) do
    [
      "Manual approval fallback: browser did not open automatically; ask for explicit approval in chat or open the URL manually."
    ]
  end

  defp manual_approval_lines(_review, _review_open), do: []

  defp review_feedback_lines(%{feedback_notes: notes}) when is_binary(notes) and notes != "",
    do: ["Feedback: #{notes}"]

  defp review_feedback_lines(_review), do: []

  defp format_review_feedback_error(%{feedback_notes: notes})
       when is_binary(notes) and notes != "" do
    " Feedback: #{notes}"
  end

  defp format_review_feedback_error(_review), do: ""

  defp review_runtime_context_from_env do
    %{
      "session_id" => System.get_env("CONTROLKEEL_SESSION_ID"),
      "task_id" => System.get_env("CONTROLKEEL_TASK_ID"),
      "agent_id" => System.get_env("CONTROLKEEL_AGENT_ID"),
      "thread_id" => System.get_env("CONTROLKEEL_THREAD_ID"),
      "host_session_id" => System.get_env("CONTROLKEEL_HOST_SESSION_ID"),
      "project_root" => System.get_env("CONTROLKEEL_PROJECT_ROOT"),
      "browser_embed" =>
        System.get_env("CONTROLKEEL_REVIEW_EMBED") || System.get_env("CONTROLKEEL_BROWSER_EMBED")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp review_cli_payload(review, extra) do
    %{
      "review" => %{
        "id" => review.id,
        "title" => review.title,
        "status" => review.status,
        "review_type" => review.review_type,
        "session_id" => review.session_id,
        "task_id" => review.task_id,
        "feedback_notes" => review.feedback_notes,
        "submitted_by" => review.submitted_by,
        "reviewed_by" => review.reviewed_by,
        "annotations" => review.annotations
      }
    }
    |> maybe_put_agent_feedback(review)
    |> Map.merge(extra)
  end

  defp maybe_put_agent_feedback(payload, %{status: "denied"} = review) do
    Map.put(payload, "agent_feedback", ReviewBridge.agent_feedback(review))
  end

  defp maybe_put_agent_feedback(payload, _review), do: payload

  defp cli_error(prefix, reason, options, extra_payload \\ %{}) do
    message = "#{prefix}: #{format_cli_error(reason)}"

    if options[:json] do
      {:error, Jason.encode!(Map.merge(%{"error" => message}, extra_payload))}
    else
      {:error, message}
    end
  end

  defp review_lines(review, recommendation_label) do
    decision =
      case review["decision"] do
        "block" -> "blocked"
        "warn" -> "needs review"
        _ -> "allowed"
      end

    base_lines = [
      review["summary"],
      "#{String.capitalize(recommendation_label)} recommendation: #{decision}.",
      "Files reviewed: #{review["files_reviewed"]}",
      "Chunks reviewed: #{review["chunks_reviewed"]}",
      "Added lines reviewed: #{review["added_lines_reviewed"]}",
      "Findings: #{get_in(review, ["finding_totals", "total"]) || 0}"
    ]

    persisted_lines =
      case review["persisted_finding_ids"] || [] do
        [] -> []
        ids -> ["Persisted findings: #{Enum.join(Enum.map(ids, &to_string/1), ", ")}"]
      end

    finding_lines =
      Enum.map(review["findings"] || [], fn finding ->
        location =
          [finding["path"], finding["kind"]]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" / ")

        severity = "#{finding["severity"]}/#{finding["decision"]}"

        case location do
          "" -> "  [#{severity}] #{finding["rule_id"]}: #{finding["plain_message"]}"
          _ -> "  [#{severity}] #{finding["rule_id"]} @ #{location}: #{finding["plain_message"]}"
        end
      end)

    base_lines ++ persisted_lines ++ finding_lines
  end

  defp release_ready_lines(readiness) do
    base_lines = [
      "Release readiness: #{readiness["status"]}",
      readiness["summary"],
      "Session: #{readiness["session_title"]} (##{readiness["session_id"]})"
    ]

    proof_lines =
      case readiness["proof"] do
        nil ->
          ["Proof: none"]

        proof ->
          ["Proof: ##{proof["id"]} v#{proof["version"]} (deploy-ready: #{proof["deploy_ready"]})"]
      end

    findings = readiness["findings"] || %{}

    evidence_lines = [
      "Open findings: #{findings["open"] || 0}",
      "Blocked findings: #{findings["blocked"] || 0}",
      "Escalated findings: #{findings["escalated"] || 0}",
      "High/critical unresolved: #{findings["high_or_critical"] || 0}",
      "Smoke satisfied: #{get_in(readiness, ["smoke", "satisfied"]) || false}",
      "Provenance satisfied: #{get_in(readiness, ["provenance", "satisfied"]) || false}"
    ]

    reason_lines = Enum.map(readiness["reasons"] || [], &"  - #{&1}")

    base_lines ++ proof_lines ++ evidence_lines ++ reason_lines
  end

  defp binding_session_id(project_root) do
    case ProjectBinding.read_effective(project_root) do
      {:ok, binding, _mode} -> binding["session_id"]
      _ -> nil
    end
  end

  defp github_metadata_from_env do
    %{
      "event_name" => System.get_env("GITHUB_EVENT_NAME"),
      "repository" => System.get_env("GITHUB_REPOSITORY"),
      "ref" => System.get_env("GITHUB_REF"),
      "sha" => System.get_env("GITHUB_SHA"),
      "run_id" => System.get_env("GITHUB_RUN_ID"),
      "base_ref" => System.get_env("GITHUB_BASE_REF"),
      "head_ref" => System.get_env("GITHUB_HEAD_REF")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp standalone_wrapper_runtime? do
    System.get_env("__BURRITO") not in [nil, ""]
  end

  defp plain_arguments do
    plain_arguments_provider().()
    |> Enum.map(&to_string/1)
  end

  defp plain_arguments_provider do
    Application.get_env(:controlkeel, :cli_plain_arguments_provider, &:init.get_plain_arguments/0)
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp require_integer_option(nil, option), do: {:error, {:missing_option, option}}
  defp require_integer_option(value, _option) when is_integer(value), do: {:ok, value}

  defp require_integer_option(value, _option) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp require_string_option(nil, option), do: {:error, {:missing_option, option}}
  defp require_string_option("", option), do: {:error, {:missing_option, option}}
  defp require_string_option(value, _option), do: {:ok, to_string(value)}

  defp parse_telemetry_level(value) do
    case ControlKeel.Cloud.TelemetryConfig.parse_level(value) do
      {:ok, :disabled} -> {:error, :invalid_level}
      {:ok, level} -> {:ok, level}
      :error -> {:error, :invalid_level}
    end
  end

  defp maybe_render_compliance_template(bundle, nil), do: {:ok, bundle}
  defp maybe_render_compliance_template(bundle, ""), do: {:ok, bundle}

  defp maybe_render_compliance_template(bundle, template) do
    ControlKeel.Cloud.ComplianceTemplate.render(bundle, template)
  end

  defp maybe_sign_audit_export(payload, %{sign: true} = options) do
    case options[:signing_key_env] do
      nil ->
        {:error, :missing_signing_key_env}

      "" ->
        {:error, :missing_signing_key_env}

      env ->
        case System.get_env(env) do
          nil -> {:error, {:missing_signing_key, env}}
          "" -> {:error, {:missing_signing_key, env}}
          key -> {:ok, ControlKeel.Cloud.AuditExportSigner.sign(payload, key, key_id: env)}
        end
    end
  end

  defp maybe_sign_audit_export(payload, _options), do: {:ok, payload}

  defp baseline_tool_count(baseline) do
    baseline
    |> ControlKeel.Cloud.WorkspaceBaseline.decode()
    |> map_size()
  end

  defp format_repo_error(nil), do: ""
  defp format_repo_error(msg), do: " — " <> msg

  defp format_value_hint(nil), do: ""
  defp format_value_hint(hint), do: " " <> hint

  defp resolve_audit_scope(options) do
    workspace_slug = options[:workspace]
    org_slug = options[:org]

    cond do
      workspace_slug && org_slug ->
        {:error, :scope_conflict}

      workspace_slug ->
        case ControlKeel.Repo.get_by(ControlKeel.Mission.Workspace, slug: workspace_slug) do
          nil -> {:error, :unknown_workspace}
          ws -> {:ok, [workspace_id: ws.id]}
        end

      org_slug ->
        case ControlKeel.Accounts.get_org_by_slug(org_slug) do
          nil -> {:error, :unknown_org}
          org -> {:ok, [org_id: org.id]}
        end

      true ->
        {:error, :scope_required}
    end
  end

  defp parse_optional_datetime(nil, _name), do: {:ok, nil}
  defp parse_optional_datetime("", _name), do: {:ok, nil}

  defp parse_optional_datetime(value, name) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> {:error, {:invalid_datetime, name}}
    end
  end

  defp maybe_append(opts, _key, nil), do: opts
  defp maybe_append(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_integer_arg(value, name) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "Invalid #{name}: #{value}"}
    end
  end

  defp validate_runtime_target(runtime) do
    if runtime in ControlKeel.Cloud.RunPackage.valid_runtimes() do
      :ok
    else
      {:error,
       "Unknown runtime '#{runtime}'. Valid runtimes: " <>
         Enum.join(ControlKeel.Cloud.RunPackage.valid_runtimes(), ", ")}
    end
  end

  defp validate_budget_cents(nil), do: {:ok, 0}
  defp validate_budget_cents(n) when is_integer(n) and n >= 0, do: {:ok, n}
  defp validate_budget_cents(_), do: {:error, "--budget-cents must be a non-negative integer"}

  defp parse_scopes(nil), do: nil
  defp parse_scopes(""), do: nil
  defp parse_scopes(value) when is_binary(value), do: value

  defp build_cloud_payload(task, options) do
    base = %{
      "task_title" => task.title,
      "validation_gate" => task.validation_gate,
      "note" => options[:note]
    }

    base = Enum.reject(base, fn {_k, v} -> v in [nil, ""] end) |> Map.new()

    case cloud_github_bindings(task) do
      [] -> base
      bindings -> Map.put(base, "github_repos", bindings)
    end
  end

  defp cloud_github_bindings(task) do
    alias ControlKeel.Mission

    case Mission.get_session(task.session_id) do
      %{workspace_id: ws_id} when is_integer(ws_id) ->
        ws_id
        |> Mission.list_github_repos()
        |> Enum.map(fn b ->
          %{
            "owner" => b.owner,
            "repo" => b.repo,
            "default_branch" => b.default_branch,
            "installation_id" => b.installation_id,
            "url" => "https://github.com/#{b.owner}/#{b.repo}"
          }
          |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
          |> Map.new()
        end)

      _ ->
        []
    end
  end

  @doc false
  # Capture git remote/branch/commit_sha for the cloud handoff.
  #
  # Explicit CLI overrides win. Otherwise we shell out to git in the given
  # project_root. Missing or non-git roots return nil for each field — the
  # cloud server treats nil as "no provable revision" and the operator can
  # decide whether to accept that for their runtime.
  def capture_git_metadata(project_root, options) do
    %{
      repo_url: options[:repo_url] || detect_git_remote(project_root),
      branch: options[:branch] || detect_git_branch(project_root),
      commit_sha: options[:commit_sha] || detect_git_commit_sha(project_root)
    }
  end

  defp detect_git_remote(nil), do: nil

  defp detect_git_remote(project_root) do
    case System.cmd("git", ["remote", "get-url", "origin"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {url, 0} -> String.trim(url)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp detect_git_branch(nil), do: nil

  defp detect_git_branch(project_root) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {branch, 0} ->
        case String.trim(branch) do
          "" -> nil
          "HEAD" -> nil
          name -> name
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp detect_git_commit_sha(nil), do: nil

  defp detect_git_commit_sha(project_root) do
    case System.cmd("git", ["rev-parse", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {sha, 0} ->
        case String.trim(sha) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join("; ")
  end

  defp format_changeset_errors(other), do: inspect(other)

  defp format_url(nil), do: ""
  defp format_url(url), do: "  url=#{url}"

  defp format_note(nil), do: ""
  defp format_note(""), do: ""
  defp format_note(note), do: "  note=#{note}"

  defp telemetry_level_list_text do
    ControlKeel.Cloud.TelemetryConfig.opt_in_levels()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(" | ")
  end

  defp selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  defp selected_base_url(_status), do: "default"

  defp ensure_attach_project(project_root, overrides) do
    ensure_local_project(project_root, overrides, sync_attached_agents: false)
  end

  defp ensure_local_project(project_root, overrides \\ %{}, opts \\ []) do
    project_root = ProjectRoot.resolve(project_root)
    sync_attached_agents? = Keyword.get(opts, :sync_attached_agents, true)

    with {:ok, binding, session, mode} <-
           LocalProject.load_or_bootstrap(project_root, overrides, ephemeral_ok: true) do
      if sync_attached_agents? do
        case AttachedAgentSync.sync(binding, project_root, mode: mode) do
          {:ok, synced_binding, _changes} -> {:ok, synced_binding, session, mode}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, binding, session, mode}
      end
    end
  end

  defp binding_write_mode(binding) do
    case get_in(binding, ["bootstrap", "mode"]) do
      "ephemeral" -> :ephemeral
      _ -> :project
    end
  end

  defp bootstrap_lines(project_root) do
    snapshot = SetupAdvisor.snapshot(project_root)
    status = ProviderBroker.status(project_root)
    bootstrap = status["bootstrap"]

    [
      "Project root: #{snapshot["project_root"]}.",
      SetupAdvisor.detected_hosts_line(snapshot),
      "Bootstrap mode: #{bootstrap["mode"]}.",
      "Provider source: #{status["selected_source"]}.",
      "Provider: #{status["selected_provider"]}.",
      "Auth mode: #{status["selected_auth_mode"]}.",
      "Auth owner: #{status["selected_auth_owner"]}.",
      "Core loop: #{SetupAdvisor.core_loop()}."
    ]
  end

  defp load_rules_payload(nil), do: {:ok, []}

  defp load_rules_payload(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      case decoded do
        %{"entries" => _entries} = wrapped -> {:ok, wrapped}
        entries when is_list(entries) -> {:ok, entries}
        other -> {:error, {:invalid_rules_payload, other}}
      end
    else
      {:error, :enoent} ->
        {:error, :rules_file_not_found}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp format_ms(nil), do: "Not recorded"
  defp format_ms(value), do: "#{value}ms"

  defp format_provider_bridge(%{supported: true, provider: provider, mode: mode}),
    do: "#{mode}: #{provider}"

  defp format_provider_bridge(%{supported: true, mode: mode}), do: mode
  defp format_provider_bridge(%{mode: "ck_owned"}), do: "ck-owned"
  defp format_provider_bridge(%{mode: "none"}), do: "none"
  defp format_provider_bridge(_bridge), do: "none"

  defp emit_attach_succeeded(binding, project_root, attached_agent) do
    root = Path.expand(project_root)

    if is_integer(binding["session_id"]) do
      _ = Mission.attach_session_runtime_context(binding["session_id"], %{"project_root" => root})

      _ =
        ControlKeel.SessionTranscript.record(%{
          session_id: binding["session_id"],
          event_type: "session.attach",
          actor: "cli",
          summary: "Attached #{attached_agent["server_name"] || "agent"} to ControlKeel.",
          body: "Project root: #{root}",
          payload: %{
            "project_root" => root,
            "server_name" => attached_agent["server_name"],
            "scope" => attached_agent["scope"]
          }
        })
    end

    :telemetry.execute(
      [:controlkeel, :claude, :attach, :succeeded],
      %{count: 1},
      %{
        session_id: binding["session_id"],
        workspace_id: binding["workspace_id"],
        project_root: root,
        server_name: attached_agent["server_name"],
        scope: attached_agent["scope"]
      }
    )
  end

  defp attach_guidance_lines(agent) do
    case AgentIntegration.get(agent) do
      nil ->
        Distribution.current_install_lines()

      integration ->
        [
          integration.preferred_target && "Companion target: #{integration.preferred_target}.",
          "Support class: #{integration.support_class}.",
          "Supported scope: #{Enum.join(integration.supported_scopes, ", ")}.",
          "Required CK tools: #{Enum.join(integration.required_mcp_tools, ", ")}.",
          "Auto-bootstrap: #{if(integration.auto_bootstrap, do: "enabled", else: "disabled")}.",
          "Auth mode: #{integration.auth_mode}.",
          "Auth owner: #{AgentIntegration.auth_owner(integration)}.",
          "MCP mode: #{integration.mcp_mode}.",
          "Skills mode: #{integration.skills_mode}.",
          "Provider bridge: #{format_provider_bridge(integration.provider_bridge)}.",
          "Core loop: #{SetupAdvisor.core_loop()}.",
          "Next: controlkeel status.",
          integration.upstream_docs_url && "Upstream docs: #{integration.upstream_docs_url}"
        ]
        |> Enum.reject(&is_nil/1)
        |> Kernel.++(cloud_guidance_lines())
        |> Kernel.++(Distribution.current_install_lines())
    end
  end

  defp cloud_guidance_lines do
    case ControlKeel.Cloud.WorkspaceIdentity.load() do
      {:ok, identity} ->
        [
          "",
          "Cloud — already connected (workspace #{identity.workspace_id}).",
          "  controlkeel cloud doctor              # verify the cloud-mode boundary",
          "  controlkeel telemetry status          # check sync state and queue depth"
        ]

      _ ->
        [
          "",
          "Cloud — optional next step (sync findings, proofs, and approvals across a team):",
          "  controlkeel cloud connect --enroll https://controlkeel.com",
          "  # or your self-host URL, e.g. https://govern.acme.com (see docs/self-hosting.md)",
          "  controlkeel cloud doctor              # verify the cloud-mode boundary"
        ]
    end
  end

  defp resolve_project_root(options, project_root) do
    options[:project_root] ||
      project_root
      |> ProjectRoot.resolve()
  end

  defp maybe_line(nil, _prefix), do: []
  defp maybe_line(line, prefix), do: ["#{prefix}#{line}"]

  defp native_attach_lines("claude-code", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("claude-standalone", project_root,
             scope: attach_scope("claude-code", options)
           ) do
        {:ok, %{destination: destination, agent_destination: agent_destination} = result} ->
          settings_line =
            case Map.get(result, :settings_destination) do
              nil -> []
              path -> ["Installed Claude hooks at #{path}."]
            end

          instructions_line =
            case Map.get(result, :instructions_destination) do
              nil -> []
              false -> []
              path -> ["Installed CLAUDE.md at #{path}."]
            end

          [
            "Installed Claude native skills at #{destination}.",
            "Installed Claude companion agent at #{agent_destination}."
          ] ++ settings_line ++ instructions_line

        {:error, reason} ->
          ["Native Claude skills were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines("cline", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("cline-native", project_root, scope: attach_scope("cline", options)) do
        {:ok, %{destination: destination} = result} ->
          [
            "Installed Cline skills at #{destination}."
          ] ++
            maybe_attach_line(
              "Installed Cline MCP companion",
              Map.get(result, :agent_destination)
            ) ++
            maybe_attach_line("Installed Cline rules", Map.get(result, :rules_destination)) ++
            maybe_attach_line(
              "Installed Cline workflows",
              Map.get(result, :workflows_destination)
            )

        {:error, reason} ->
          ["Native Cline files were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines("goose", project_root, options) do
    if native_attach_skipped?(options) do
      []
    else
      case Skills.install("goose-native", project_root, scope: "project") do
        {:ok, %{destination: destination} = result} ->
          [
            "Installed Goose project hints at #{destination}."
          ] ++
            maybe_attach_line(
              "Installed Goose workflow recipes",
              Map.get(result, :workflows_destination)
            ) ++
            maybe_attach_line(
              "Installed Goose companion bundle",
              Map.get(result, :agent_destination)
            )

        {:error, reason} ->
          ["Native Goose files were not installed: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines(agent, project_root, options)
       when agent in [
              "cursor",
              "windsurf",
              "kiro",
              "kilo",
              "amp",
              "augment",
              "opencode",
              "gemini-cli",
              "continue",
              "aider"
            ] do
    if native_attach_skipped?(options) do
      []
    else
      target =
        %{
          "cursor" => "cursor-native",
          "windsurf" => "windsurf-native",
          "kiro" => "kiro-native",
          "kilo" => "kilo-native",
          "amp" => "amp-native",
          "augment" => "augment-native",
          "opencode" => "opencode-native",
          "gemini-cli" => "gemini-cli-native",
          "continue" => "continue-native",
          "aider" => "instructions-only"
        }[agent]

      case if(target,
             do: Skills.install(target, project_root, scope: "project"),
             else: Skills.export("instructions-only", project_root, scope: "export")
           ) do
        {:ok, %{destination: destination}} ->
          [
            "Prepared native companion files for #{display_attach_agent(agent)}.",
            "Destination: #{destination}"
          ]

        {:ok, plan} ->
          [
            "Prepared native instruction snippets for #{display_attach_agent(agent)}.",
            "Instructions bundle: #{plan.output_dir}"
          ]

        {:error, reason} ->
          ["Instruction bundle was not prepared: #{inspect(reason)}"]
      end
    end
  end

  defp native_attach_lines(_agent, _project_root, _options), do: []

  defp native_attach_skipped?(options) do
    Keyword.get(options, :mcp_only, false) or Keyword.get(options, :no_native, false)
  end

  defp maybe_install_codex_native(project_root, scope, options) do
    if native_attach_skipped?(options) do
      {:ok, nil}
    else
      Skills.install("codex", project_root, scope: scope)
    end
  end

  defp codex_attach_install_lines(nil), do: []

  defp codex_attach_install_lines(install_result) do
    lines = [
      "Installed Codex skills at #{install_result[:destination]}.",
      "Installed Codex companion agent at #{install_result[:agent_destination]}.",
      "Installed Codex review commands at #{install_result[:commands_destination]}."
    ]

    compat_destination = install_result[:compat_destination]

    cond do
      is_nil(compat_destination) ->
        lines

      compat_destination == install_result[:destination] ->
        lines

      true ->
        lines ++ ["Installed open-standard compatibility skills at #{compat_destination}."]
    end
  end

  defp attach_scope(agent, options) do
    options[:scope] ||
      case AgentIntegration.get(agent) do
        %AgentIntegration{default_scope: scope} when is_binary(scope) -> scope
        _ -> "project"
      end
  end

  defp validate_attach_scope(agent, options) do
    scope = attach_scope(agent, options)

    case AgentIntegration.get(agent) do
      %AgentIntegration{supported_scopes: scopes, label: label}
      when is_list(scopes) and scopes != [] ->
        if scope in scopes do
          {:ok, scope}
        else
          {:error,
           "Unsupported scope `#{scope}` for #{label}. Supported scopes: #{Enum.join(scopes, ", ")}."}
        end

      _ ->
        {:ok, scope}
    end
  end

  defp display_attach_agent(agent), do: AgentIntegration.label(agent)

  # ─── IDE MCP attachment helpers ──────────────────────────────────────────────

  defp attach_to_cursor(command_spec) do
    config_path = cursor_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "cursor")
  end

  defp attach_to_windsurf(command_spec) do
    config_path = windsurf_mcp_config_path()
    write_ide_mcp_config(config_path, "controlkeel", command_spec, "windsurf")
  end

  defp cursor_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([
          System.get_env("APPDATA") || home,
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      {:unix, :darwin} ->
        Path.join([
          home,
          "Library",
          "Application Support",
          "Cursor",
          "User",
          "globalStorage",
          "cursor.mcp.json"
        ])

      _ ->
        Path.join([home, ".config", "Cursor", "User", "globalStorage", "cursor.mcp.json"])
    end
  end

  defp windsurf_mcp_config_path do
    home = user_home()
    Path.join([home, ".codeium", "windsurf", "mcp_config.json"])
  end

  defp write_ide_mcp_config(config_path, server_name, command_spec, ide_key) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing = read_json_map(config_path)

    updated =
      if ide_key in ["opencode", "kilo"] do
        mcp = Map.get(existing, "mcp", %{})

        entry = %{
          "type" => "local",
          "command" => [command | args],
          "enabled" => true
        }

        Map.put(
          existing,
          "mcp",
          Map.put(mcp, server_name, entry)
        )
      else
        mcpServers = Map.get(existing, "mcpServers", %{})

        Map.put(
          existing,
          "mcpServers",
          Map.put(mcpServers, server_name, %{
            "command" => command,
            "args" => args
          })
        )
      end

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => ide_key,
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp read_json_map(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{} = decoded} -> decoded
          _ -> %{}
        end

      _ ->
        %{}
    end || %{}
  end

  defp ensure_stdio_server_running(timeout_ms) do
    case wait_for_stdio_server(timeout_ms) do
      pid when is_pid(pid) ->
        pid

      nil ->
        _ = maybe_start_stdio_server_child()
        wait_for_stdio_server(timeout_ms)
    end
  end

  defp maybe_start_stdio_server_child do
    opts = [
      name: ControlKeel.MCP.Server.stdio_registered_name(),
      input: :stdio,
      output: :stdio
    ]

    case Process.whereis(ControlKeel.Supervisor) do
      pid when is_pid(pid) ->
        child = {ControlKeel.MCP.Server, opts}

        case Supervisor.start_child(ControlKeel.Supervisor, child) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          :ignore -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :error
        end

      nil ->
        case ControlKeel.MCP.Server.start_link(opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :error
        end
    end
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp wait_for_stdio_server(timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_stdio_server_until(deadline)
  end

  defp wait_for_stdio_server_until(deadline_ms) do
    case Process.whereis(ControlKeel.MCP.Server.stdio_registered_name()) do
      pid when is_pid(pid) ->
        pid

      nil ->
        if System.monotonic_time(:millisecond) < deadline_ms do
          Process.sleep(25)
          wait_for_stdio_server_until(deadline_ms)
        else
          nil
        end
    end
  end

  # ── Additional IDE MCP config paths ──────────────────────────────────────────

  defp kiro_mcp_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, ".kiro", "settings", "mcp.json"])

      _ ->
        Path.join([home, ".kiro", "settings", "mcp.json"])
    end
  end

  defp kilo_config_path do
    Path.join([user_home(), ".config", "kilo", "kilo.json"])
  end

  defp amp_mcp_config_path do
    Path.join([user_home(), ".config", "amp", "mcp.json"])
  end

  defp augment_mcp_config_path do
    Path.join([user_home(), ".augment", "settings.json"])
  end

  defp opencode_mcp_config_path do
    Path.join([user_home(), ".config", "opencode", "opencode.json"])
  end

  defp gemini_cli_config_path do
    Path.join([user_home(), ".gemini", "settings.json"])
  end

  defp cline_mcp_config_path do
    base = System.get_env("CLINE_DIR") || Path.join(user_home(), ".cline")
    Path.join([base, "data", "settings", "cline_mcp_settings.json"])
  end

  defp continue_config_path do
    home = user_home()

    case :os.type() do
      {:win32, _} ->
        Path.join([System.get_env("APPDATA") || home, "Roaming", "Continue", "config.json"])

      _ ->
        Path.join([home, ".continue", "config.json"])
    end
  end

  # Continue uses an array-based mcpServers format, unlike Cursor/Windsurf dict format
  defp write_continue_mcp_config(config_path, server_name, command_spec) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []

    existing =
      case File.read(config_path) do
        {:ok, c} -> Jason.decode(c) |> elem(1)
        _ -> %{}
      end || %{}

    servers = Map.get(existing, "mcpServers", [])
    filtered = Enum.reject(servers, &(Map.get(&1, "name") == server_name))
    new_entry = %{"name" => server_name, "command" => command, "args" => args}
    updated = Map.put(existing, "mcpServers", filtered ++ [new_entry])

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n") do
      {:ok,
       %{
         "server_name" => server_name,
         "ide" => "continue",
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  # Aider uses a YAML config file (.aider.conf.yml) at the project root
  defp attach_to_aider(command_spec, project_root) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []
    config_path = Path.join(project_root, ".aider.conf.yml")

    existing =
      case File.read(config_path) do
        {:ok, c} -> c
        _ -> ""
      end

    # Remove any prior controlkeel block, then append the new one
    cleaned =
      Regex.replace(
        ~r/\nmcpservers:(\n  controlkeel:[^\n]*(\n    [^\n]+)*)+/,
        existing,
        ""
      )

    args_line =
      case args do
        [] -> ""
        values -> "    args: [#{Enum.map_join(values, ", ", &~s(\"#{&1}\"))}]\n"
      end

    entry = "\nmcpservers:\n  controlkeel:\n    command: #{command}\n" <> args_line

    with :ok <- File.write(config_path, String.trim_trailing(cleaned) <> entry) do
      {:ok,
       %{
         "server_name" => "controlkeel",
         "ide" => "aider",
         "config_path" => config_path,
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp goose_config_path do
    Path.join([user_home(), ".config", "goose", "config.yaml"])
  end

  defp attach_to_goose(command_spec, project_root) do
    command = command_spec[:command] || command_spec["command"]
    args = command_spec[:args] || command_spec["args"] || []
    config_path = goose_config_path()

    existing = read_yaml_file(config_path)

    extension =
      %{
        "enabled" => true,
        "type" => "stdio",
        "name" => "ControlKeel",
        "description" => "ControlKeel governance MCP server",
        "cmd" => command,
        "args" => args,
        "timeout" => 300
      }

    updated =
      Map.put(
        existing,
        "extensions",
        existing
        |> Map.get("extensions", %{})
        |> normalize_yaml_map()
        |> Map.put("controlkeel", extension)
      )

    with :ok <- File.mkdir_p(Path.dirname(config_path)),
         :ok <- File.write(config_path, yaml_document(updated)) do
      {:ok,
       %{
         "server_name" => "controlkeel",
         "ide" => "goose",
         "config_path" => config_path,
         "project_root" => Path.expand(project_root),
         "command" => command,
         "args" => args,
         "attached_at" =>
           DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  defp read_yaml_file(path) do
    case YamlElixir.read_from_file(path) do
      {:ok, value} when is_map(value) -> value
      _ -> %{}
    end
  end

  defp normalize_yaml_map(value) when is_map(value), do: value
  defp normalize_yaml_map(_value), do: %{}

  defp yaml_document(value) do
    yaml_encode(value, 0)
  end

  defp yaml_encode(value, indent) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("", fn {key, nested} ->
      yaml_key_value(to_string(key), nested, indent)
    end)
  end

  defp yaml_encode(value, indent) when is_list(value) do
    Enum.map_join(value, "", fn
      nested when is_map(nested) ->
        "#{String.duplicate(" ", indent)}-\n" <> yaml_encode(nested, indent + 2)

      nested ->
        "#{String.duplicate(" ", indent)}- #{yaml_scalar(nested)}\n"
    end)
  end

  defp yaml_key_value(key, value, indent) when is_map(value) do
    if map_size(value) == 0 do
      "#{String.duplicate(" ", indent)}#{key}: {}\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) when is_list(value) do
    if value == [] do
      "#{String.duplicate(" ", indent)}#{key}: []\n"
    else
      "#{String.duplicate(" ", indent)}#{key}:\n" <> yaml_encode(value, indent + 2)
    end
  end

  defp yaml_key_value(key, value, indent) do
    "#{String.duplicate(" ", indent)}#{key}: #{yaml_scalar(value)}\n"
  end

  defp yaml_scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_scalar(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp yaml_scalar(nil), do: "null"
  defp yaml_scalar(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp auto_attach_claude_code(project_root) do
    claude_dir = Path.join(user_home(), ".claude")
    command_spec = ProjectBinding.mcp_command_spec(project_root)

    cond do
      not File.dir?(claude_dir) ->
        {:skip, "claude-code not found on this system"}

      true ->
        case ClaudeCLI.attach_local(project_root, command_spec.command, command_spec.args) do
          {:ok, result} ->
            _ = Skills.install("claude-standalone", project_root, scope: "user")

            emit_attach_succeeded(
              %{"session_id" => nil, "workspace_id" => nil},
              project_root,
              result
            )

            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  defp format_domain_packs(packs) when is_binary(packs), do: format_domain_packs([packs])

  defp format_domain_packs(packs) when is_list(packs) do
    packs
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&Intent.pack_label/1)
    |> Enum.join(", ")
  end

  defp format_money(nil), do: "unlimited"
  defp format_money(cents), do: :io_lib.format("$~.2f", [cents / 100]) |> IO.iodata_to_binary()
  defp format_duration(nil), do: "not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp user_home do
    System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()
  end

  defp github_repo_attached_agent(agent, scope, %{destination: destination}) do
    %{
      "target" => "github-repo",
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp github_repo_attached_agent(agent, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => plan.target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp attach_bundle_target(target, project_root, scope, options) do
    if native_attach_skipped?(options) do
      Skills.export(target, project_root, scope: "export")
    else
      Skills.install(target, project_root, scope: scope)
    end
  end

  defp bundled_attached_agent(agent, target, scope, %{destination: destination} = result) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "destination" => destination,
      "config_destination" => Map.get(result, :agent_destination),
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp bundled_attached_agent(agent, target, scope, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    %{
      "target" => target,
      "agent" => agent,
      "scope" => scope,
      "output_dir" => plan.output_dir,
      "attached_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp bundle_attach_lines(agent, %{destination: destination} = result) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Installed bundle at #{destination}."
    ] ++
      if(Map.has_key?(result, :agent_destination),
        do: ["Config destination: #{result.agent_destination}."],
        else: []
      )
  end

  defp bundle_attach_lines(agent, %ControlKeel.Skills.SkillExportPlan{} = plan) do
    [
      "Prepared ControlKeel companion files for #{display_attach_agent(agent)}.",
      "Output: #{plan.output_dir}"
    ]
  end

  defp maybe_attach_line(_label, nil), do: []
  defp maybe_attach_line(label, path), do: ["#{label} at #{path}."]
end
