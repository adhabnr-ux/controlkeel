defmodule ControlKeel.CLI.Dispatch.Core do
  @moduledoc false

  alias ControlKeel.Analytics
  alias ControlKeel.AutonomyLoop
  alias ControlKeel.Budget
  alias ControlKeel.Help
  alias ControlKeel.LocalProject
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProjectBinding
  alias ControlKeel.Updater
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Proxy
  alias ControlKeel.SetupAdvisor
  alias ControlKeel.Mission.TaskAugmentation
  import ControlKeel.CLI, except: [run_command: 2]

  def run_command(%{command: :serve}, _project_root), do: :ok

  def run_command(%{command: :capabilities, options: options}, _project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      payload = ControlKeel.CLI.Capabilities.payload()

      render_format(format, payload, &ControlKeel.CLI.Capabilities.lines/1)
    end
  end

  def run_command(%{command: :doctor, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options) do
      root = resolve_project_root(options, project_root)
      payload = ControlKeel.CLI.Doctor.payload(root, version())

      render_format(format, payload, &ControlKeel.CLI.Doctor.lines/1)
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

  def run_command(%{command: :me, options: options}, project_root) do
    with {:ok, format} <- effective_cli_format(options),
         {:ok, _binding, default_session, _mode} <- ensure_local_project(project_root) do
      session_id = options[:session_id] || default_session.id

      payload = ControlKeel.Learning.EngineerMirror.build(session_id)

      render_format(format, payload, fn p -> [render_engineer_mirror(p)] end)
    end
  end

  def run_command(%{command: :status, options: options}, project_root) do
    project_root = resolve_project_root(options, project_root)

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
end
