defmodule ControlKeel.Observability.Promotion do
  @moduledoc """
  Pure policy for deciding when recurring agent work is ready to become a
  deterministic check.

  This module intentionally does not mutate candidates, run benchmarks, or
  invoke an agent. It turns existing candidate and benchmark evidence into a
  stable decision that callers can use to choose the next workflow step.
  """

  @type decision :: %{
          state: String.t(),
          reason: String.t(),
          next_action: String.t(),
          deterministic: true,
          human_gate_required: boolean()
        }

  @spec evaluate(map() | nil, map()) :: decision()
  def evaluate(candidate, evidence \\ %{}) do
    candidate = candidate || %{}
    evidence = evidence || %{}
    metadata = field(candidate, :metadata) || %{}

    cond do
      failed_evidence?(evidence) or reopened?(metadata) ->
        decision(
          "reopen",
          "benchmark evidence failed or the candidate was reopened after a regression",
          "Investigate the miss, update the guardrail, and rerun the bounded regression flow.",
          true
        )

      passed_evidence?(evidence, metadata) and approved?(candidate, evidence, metadata) ->
        decision(
          "promote",
          "human approval and passing benchmark evidence are both recorded",
          "Use the deterministic check or workflow as the default path; reserve the agent for exceptions.",
          false
        )

      passed_evidence?(evidence, metadata) ->
        decision(
          "review",
          "benchmark evidence passes but human approval is not recorded",
          "Obtain human approval before promoting this behavior into a deterministic workflow.",
          true
        )

      field(candidate, :status) == "rejected" ->
        decision(
          "discover",
          "the candidate was rejected and has no approved repeatable contract",
          "Keep the work agent-led until a narrower, reviewable behavior is identified.",
          true
        )

      field(candidate, :human_gate_required) == false ->
        decision(
          "discover",
          "repeatability has not been proven yet",
          "Collect bounded evidence before encoding the behavior as a deterministic check.",
          false
        )

      true ->
        decision(
          "review",
          "a recurring behavior is identified but its promotion gate is incomplete",
          "Review the candidate and create bounded regression coverage before promotion.",
          true
        )
    end
  end

  defp decision(state, reason, next_action, human_gate_required) do
    %{
      state: state,
      reason: reason,
      next_action: next_action,
      deterministic: true,
      human_gate_required: human_gate_required
    }
  end

  defp failed_evidence?(evidence) do
    field(evidence, :outcome) in ["failed", "flaky"] or
      field(evidence, :all_matched) == false
  end

  defp passed_evidence?(evidence, metadata) do
    field(evidence, :outcome) == "passed" or
      field(evidence, :all_matched) == true or
      metadata_value(metadata, "lifecycle_closed_by_run", "all_matched") == true
  end

  defp reopened?(metadata), do: Map.has_key?(metadata, "lifecycle_reopened_by_run")

  defp approved?(candidate, evidence, metadata) do
    field(candidate, :status) == "approved" or
      field(evidence, :human_approved) == true or
      metadata_value(metadata, "human_approved") == true
  end

  defp metadata_value(metadata, key, nested_key \\ nil) do
    value = Map.get(metadata, key)

    if nested_key && is_map(value), do: Map.get(value, nested_key), else: value
  end

  defp field(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> nil
    end
  end
end
