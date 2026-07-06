defmodule ControlKeel.CLI.Dispatch.SandboxSecurityCodeMode do
  @moduledoc false

  alias ControlKeel.Governance.AgentMonitor
  alias ControlKeel.Governance.CircuitBreaker
  alias ControlKeel.Governance.PreCommitHook
  alias ControlKeel.ExecutionSandbox
  alias ControlKeel.Runtime.Paths
  import ControlKeel.CLI, except: [run_command: 2]

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
      config_path = Paths.config_path()
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
end
