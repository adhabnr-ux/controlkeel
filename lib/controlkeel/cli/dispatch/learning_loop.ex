defmodule ControlKeel.CLI.Dispatch.LearningLoop do
  @moduledoc false

  alias ControlKeel.Learning.OutcomeTracker
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
