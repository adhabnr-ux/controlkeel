defmodule ControlKeel.CLI.Dispatch.LearningLoop do
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
end
