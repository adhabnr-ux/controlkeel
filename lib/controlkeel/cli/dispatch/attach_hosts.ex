defmodule ControlKeel.CLI.Dispatch.AttachHosts do
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
end
