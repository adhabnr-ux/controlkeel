defmodule ControlKeel.CLI.Dispatch.MemoryContinuity do
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

end
