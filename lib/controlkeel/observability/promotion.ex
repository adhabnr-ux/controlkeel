defmodule ControlKeel.Observability.Promotion do
  @moduledoc """
  Pure policy for deciding when recurring agent work is ready to become a
  deterministic check.

  This module intentionally does not mutate candidates, run benchmarks, or
  invoke an agent. It turns existing candidate and benchmark evidence into a
  stable decision that callers can use to choose the next workflow step.

  ## Lifecycle marker semantics

  `Observability.close_eval_candidate_lifecycle_from_run!/1` overwrites the
  candidate `status` on every benchmark run (`archived` on pass, `open` on a
  miss) and appends a timestamped marker to `metadata`:

    * `lifecycle_closed_by_run` — set with `all_matched: true` on a passing run.
    * `lifecycle_reopened_by_run` — set with `all_matched: false` on a failing run.

  Old markers are **never deleted**, so the *current* lifecycle state is derived
  by comparing marker `closed_at` timestamps, not by key presence alone. This
  means a candidate that fails once and later passes again correctly recovers
  to `promote`, and a passing candidate whose approval was overwritten to
  `archived` still counts as approved (only approved candidates are ever
  materialized into benchmark scenarios).
  """

  @type decision :: %{
          state: String.t(),
          reason: String.t(),
          next_action: String.t(),
          deterministic: true,
          human_gate_required: boolean()
        }

  @spec evaluate(map() | nil, map() | nil) :: decision()
  def evaluate(candidate, evidence \\ %{}) do
    candidate = candidate || %{}
    evidence = evidence || %{}
    metadata = field(candidate, :metadata) || %{}

    cond do
      regressed?(metadata, evidence) ->
        decision(
          "reopen",
          "benchmark evidence failed or the candidate was reopened after a regression",
          "Investigate the miss, update the guardrail, and rerun the bounded regression flow.",
          true
        )

      passing?(evidence, metadata) and approved?(candidate, evidence, metadata) ->
        decision(
          "promote",
          "human approval and passing benchmark evidence are both recorded",
          "Use the deterministic check or workflow as the default path; reserve the agent for exceptions.",
          false
        )

      passing?(evidence, metadata) ->
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

  # A candidate is currently regressed when live evidence reports a failure or
  # the latest retained lifecycle marker is a reopen. We compare `closed_at`
  # timestamps because old markers are retained, not deleted.
  defp regressed?(metadata, evidence) do
    live_failure?(evidence) or latest_marker_is_reopen?(metadata)
  end

  defp live_failure?(evidence) do
    field(evidence, :outcome) in ["failed", "flaky"] or
      field(evidence, :all_matched) == false
  end

  defp latest_marker_is_reopen?(metadata) do
    reopened = metadata["lifecycle_reopened_by_run"]
    closed = metadata["lifecycle_closed_by_run"]

    reopened != nil and compare_marker_timestamps(closed, reopened) != :gt
  end

  defp passing?(evidence, metadata) do
    live_pass?(evidence) or closed_lifecycle_passes?(metadata)
  end

  defp live_pass?(evidence) do
    field(evidence, :outcome) == "passed" or field(evidence, :all_matched) == true
  end

  # A current closed marker (not overridden by a later reopen) proves a passing
  # benchmark run. `all_matched` is always true for closed markers in production,
  # but we check it defensively.
  defp closed_lifecycle_passes?(metadata) do
    closed = metadata["lifecycle_closed_by_run"]
    reopened = metadata["lifecycle_reopened_by_run"]

    closed != nil and
      closed["all_matched"] != false and
      compare_marker_timestamps(closed, reopened) != :lt
  end

  defp approved?(candidate, evidence, metadata) do
    field(candidate, :status) == "approved" or
      field(evidence, :human_approved) == true or
      metadata_value(metadata, "human_approved") == true or
      approved_by_closed_lifecycle?(metadata)
  end

  # Only approved candidates are materialized into benchmark scenarios, so a
  # current closed marker also proves prior human approval even though the
  # `status` field was overwritten to `archived` by the lifecycle transition.
  defp approved_by_closed_lifecycle?(metadata) do
    closed_lifecycle_passes?(metadata)
  end

  defp metadata_value(metadata, key), do: Map.get(metadata, key)

  # Compares the `closed_at` timestamps of the closed vs reopened markers.
  # Returns :gt when closed is newer, :lt when reopened is newer, :eq on ties
  # or when either marker is missing/unparseable.
  defp compare_marker_timestamps(nil, _reopened), do: :lt
  defp compare_marker_timestamps(_closed, nil), do: :gt

  defp compare_marker_timestamps(closed, reopened) do
    with {:ok, closed_at, _} <- DateTime.from_iso8601(closed["closed_at"] || ""),
         {:ok, reopened_at, _} <- DateTime.from_iso8601(reopened["closed_at"] || "") do
      DateTime.compare(closed_at, reopened_at)
    else
      _ -> :eq
    end
  end

  defp field(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> nil
    end
  end
end
