defmodule ControlKeel.CLI.Dispatch.AttachHosts do
  @moduledoc false

  alias ControlKeel.AgentExecution
  alias ControlKeel.AgentIntegration
  alias ControlKeel.ClaudeCLI
  alias ControlKeel.CodexConfig
  alias ControlKeel.ProviderBroker
  alias ControlKeel.ProjectBinding
  alias ControlKeel.SetupAdvisor
  alias ControlKeel.Skills
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

  def run_command(%{command: :detach, args: [agent], options: options}, project_root) do
    root = options[:project_root] || project_root

    with {:ok, binding, _session, _mode} <- load_binding_for_detach(root),
         {:ok, agent_key, attrs} <- resolve_attached(agent, binding) do
      remove_mcp_registration(agent_key, attrs, root)
      cleanup_agent_artifacts(attrs, root, options[:force])

      updated_binding = remove_agent_from_binding(binding, agent_key)
      remaining = map_size(updated_binding["attached_agents"] || %{})

      # If no agents remain, clean up the controlkeel/ directory
      if remaining == 0 and not options[:keep_binding] do
        cleanup_binding_dir(root)
      end

      {:ok, _binding} =
        if remaining > 0 do
          ProjectBinding.write_effective(
            updated_binding,
            root,
            mode: binding_write_mode(updated_binding)
          )
        else
          {:ok, updated_binding}
        end

      detach_lines(agent_key, attrs, remaining)
    else
      {:error, :no_binding} ->
        {:error, "No ControlKeel binding found. Run `controlkeel init` first."}

      {:error, {:not_attached, key}} ->
        {:error, "Agent #{key} is not attached to this project."}

      {:error, reason} ->
        {:error, "Failed to detach: #{inspect(reason)}"}
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

  defp load_binding_for_detach(root) do
    case ControlKeel.LocalProject.load(root) do
      {:ok, binding, session} -> {:ok, binding, session, "project"}
      {:error, _reason} -> {:error, :no_binding}
    end
  end

  # Resolve the *actual* key an agent was stored under in attached_agents.
  # attach is inconsistent (claude-code -> "claude_code", most others use their
  # raw dashed name), and AgentIntegration.canonical/1 returns a struct, so we
  # match against a candidate set of dash/underscore variants.
  defp resolve_attached(agent, binding) do
    agents = Map.get(binding, "attached_agents", %{})

    case Enum.find(attached_key_candidates(agent), &Map.has_key?(agents, &1)) do
      nil -> {:error, {:not_attached, agent}}
      key -> {:ok, key, Map.get(agents, key)}
    end
  end

  defp attached_key_candidates(agent) do
    canonical_id =
      case AgentIntegration.canonical(agent) do
        %{id: id} when is_binary(id) -> id
        _ -> agent
      end

    [agent, canonical_id]
    |> Enum.flat_map(&[&1, String.replace(&1, "-", "_"), String.replace(&1, "_", "-")])
    |> Enum.uniq()
  end

  # Reverse the MCP server registration attach wrote, dispatched by how each
  # host stores it. Best-effort and idempotent: a missing file/CLI is a no-op.
  defp remove_mcp_registration(agent_key, attrs, root) do
    server = attrs["server_name"] || "controlkeel"
    config_path = attrs["config_destination"] || attrs["config_path"]

    cond do
      claude_agent?(agent_key) ->
        ControlKeel.ClaudeCLI.detach_local(root, server)

      codex_agent?(agent_key) and is_binary(config_path) ->
        ControlKeel.CodexConfig.remove(config_path)

      is_binary(config_path) and String.ends_with?(config_path, ".toml") ->
        ControlKeel.CodexConfig.remove(config_path)

      is_binary(config_path) and String.ends_with?(config_path, ".json") ->
        remove_json_mcp_entry(config_path, server)

      true ->
        :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  defp claude_agent?(key), do: key in ["claude_code", "claude-code"]

  defp codex_agent?(key),
    do: key in ["codex-cli", "codex_cli", "codex-app-server", "codex_app_server", "t3code"]

  # Remove the controlkeel entry from a JSON MCP config, handling both the dict
  # forms (mcpServers / mcp) and the array form (continue). Other servers and
  # user keys are preserved; the file is only rewritten if it actually changed.
  defp remove_json_mcp_entry(config_path, server) do
    with {:ok, body} <- File.read(config_path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      updated =
        map
        |> drop_mcp_server("mcpServers", server)
        |> drop_mcp_server("mcp", server)

      if updated == map do
        :ok
      else
        File.write(config_path, Jason.encode!(updated, pretty: true) <> "\n")
      end
    else
      _ -> :ok
    end
  end

  defp drop_mcp_server(map, key, server) do
    case Map.get(map, key) do
      servers when is_map(servers) ->
        Map.put(map, key, Map.delete(servers, server))

      servers when is_list(servers) ->
        Map.put(map, key, Enum.reject(servers, &(Map.get(&1, "name") == server)))

      _ ->
        map
    end
  end

  defp remove_agent_from_binding(binding, agent_key) do
    updated_agents =
      binding
      |> Map.get("attached_agents", %{})
      |> Map.delete(agent_key)

    Map.put(binding, "attached_agents", updated_agents)
  end

  # Remove project-scope files created by attach for a specific agent.
  # Best-effort: failures to remove individual files are logged but don't fail the detach.
  defp cleanup_agent_artifacts(attrs, root, force) do
    scope = attrs["scope"] || "project"

    # Collect all destination paths that are within the project root
    destination_keys = [
      "skills_destination",
      "compat_skills_destination",
      "compat_destination",
      "agents_destination",
      "commands_destination",
      "plugins_destination",
      "rules_destination"
    ]

    destinations =
      destination_keys
      |> Enum.map(&Map.get(attrs, &1))
      |> Enum.filter(&is_binary/1)

    if scope == "project" do
      # Only remove project-scope dirs
      root_expanded = Path.expand(root)

      Enum.each(destinations, fn dest ->
        expanded = Path.expand(dest)

        if String.starts_with?(expanded, root_expanded <> "/") and File.exists?(expanded) do
          if force do
            File.rm_rf!(expanded)
          else
            # Only remove if it looks like a CK-managed dir (has our manifest)
            manifest = Path.join(expanded, ".controlkeel-skills.json")

            if File.exists?(manifest) do
              File.rm_rf!(expanded)
            end
          end
        end
      end)

      # Also clean the MCP wrapper destination
      if Map.get(attrs, "command") do
        wrapper = ProjectBinding.mcp_wrapper_path(root)

        if File.exists?(wrapper) do
          # Only remove if this was the last agent using the wrapper
          # (We check after updating the binding, so this is safe)
          :ok
        end
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  defp cleanup_binding_dir(root) do
    binding_dir = Path.join(Path.expand(root), "controlkeel")

    if File.dir?(binding_dir) do
      File.rm_rf!(binding_dir)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp detach_lines(agent_key, attrs, remaining) do
    scope = attrs["scope"] || "project"

    lines =
      [
        "Detached #{agent_key} (scope: #{scope}).",
        if(remaining > 0,
          do: "Remaining attached agents: #{remaining}",
          else: "No agents remaining. Binding directory cleaned up."
        )
      ]
      |> Enum.filter(&is_binary/1)

    {:ok, lines}
  end
end
