defmodule ControlKeel.Mission.GovernedManifest do
  @moduledoc """
  Builds an AIDLC-style governed manifest packet from existing CK runtime state.

  This module is deliberately schema-free: callers can embed the returned packet
  in review metadata, context packets, task reports, or memory records without a
  database migration.
  """

  alias ControlKeel.Mission.DecisionGates
  alias ControlKeel.Utils

  @version "1.0.0"
  @scopes ~w(new feature bugfix refactor)

  def build(attrs \\ %{}) when is_map(attrs) do
    attrs = Utils.stringify_keys(attrs)
    phase = normalize_phase(attrs["phase"] || attrs["current_phase"])
    scope = normalize_scope(attrs["scope"])
    gates = normalize_gates(attrs["gates"] || attrs["decision_gates"], phase)

    %{
      "version" => @version,
      "feature" => attrs["feature"] || attrs["goal"] || attrs["title"],
      "goal_id" => attrs["goal_id"],
      "session_id" => attrs["session_id"],
      "task_id" => attrs["task_id"],
      "scope" => scope,
      "phase" => phase,
      "status" => attrs["status"] || "active",
      "decision_gates" => gates,
      "artifacts" => normalize_list(attrs["artifacts"]),
      "validation_commands" => normalize_list(attrs["validation_commands"]),
      "current_unit" => attrs["current_unit"],
      "delegated_agents" => normalize_list(attrs["delegated_agents"]),
      "rollback_checkpoint" => attrs["rollback_checkpoint"],
      "proof_links" => normalize_list(attrs["proof_links"]),
      "active_findings" => normalize_list(attrs["active_findings"]),
      "approved_reviews" => normalize_list(attrs["approved_reviews"]),
      "context_rehydration" => context_rehydration(attrs, phase, gates),
      "updated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> drop_nil_values()
  end

  defp normalize_gates(nil, phase) do
    DecisionGates.gates()
    |> Enum.map(fn gate ->
      status = if gate["phase"] == phase, do: "active", else: "pending"
      Map.put(gate, "status", status)
    end)
  end

  defp normalize_gates(gates, _phase) when is_list(gates) do
    Enum.map(gates, fn
      gate when is_map(gate) -> Utils.stringify_keys(gate)
      gate_id -> DecisionGates.review_gate_summary(gate_id) || %{"id" => to_string(gate_id)}
    end)
  end

  defp normalize_gates(gate_id, _phase), do: normalize_gates([gate_id], nil)

  defp context_rehydration(attrs, phase, gates) do
    active_gate =
      Enum.find(gates, &(&1["status"] == "active")) || DecisionGates.preset_for_phase(phase)

    %{
      "active_gate" => active_gate && active_gate["id"],
      "approved_decisions" => normalize_list(attrs["approved_decisions"]),
      "blocked_findings" => normalize_list(attrs["blocked_findings"]),
      "proof_obligations" => normalize_list(attrs["proof_obligations"]),
      "next_valid_action" => attrs["next_valid_action"] || default_next_action(active_gate),
      "phase_handoff_identity_reset" =>
        "Treat the active phase skill and this manifest as the operating contract; ignore stale phase instructions unless re-approved."
    }
  end

  defp default_next_action(%{"id" => gate_id}), do: "resolve_or_approve_#{gate_id}"
  defp default_next_action(_), do: "call_ck_context"

  defp normalize_phase(nil), do: "context"
  defp normalize_phase(phase), do: phase |> to_string() |> String.downcase()

  defp normalize_scope(scope) when scope in @scopes, do: scope

  defp normalize_scope(scope) when is_binary(scope) do
    normalized = String.downcase(scope)
    if normalized in @scopes, do: normalized, else: "feature"
  end

  defp normalize_scope(_), do: "feature"

  defp normalize_list(nil), do: []
  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(value), do: [value]

  defp drop_nil_values(map) do
    Enum.reject(map, fn {_key, value} -> is_nil(value) end) |> Map.new()
  end
end
