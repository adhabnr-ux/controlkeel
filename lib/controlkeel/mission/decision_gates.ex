defmodule ControlKeel.Mission.DecisionGates do
  @moduledoc """
  AIDLC-inspired decision-gate presets for governed review plans.

  The gates are intentionally pure data so MCP tools, browser review, hooks, and
  skill workflows can share the same contract without requiring schema changes.
  """

  @gate_order ~w(D1_requirements D2_decomposition D3_design D4_tasks D5_deploy)

  # Maps CK plan_phase vocabulary to the closest AIDLC decision gate.
  # CK phases: ticket, research_packet, design_options, narrowed_decision,
  # implementation_plan, code_backed_plan.
  @ck_phase_to_gate %{
    "ticket" => "D1_requirements",
    "research_packet" => "D1_requirements",
    "design_options" => "D3_design",
    "narrowed_decision" => "D3_design",
    "implementation_plan" => "D4_tasks",
    "code_backed_plan" => "D4_tasks"
  }

  @gates %{
    "D1_requirements" => %{
      "id" => "D1_requirements",
      "phase" => "requirements",
      "label" => "D1 Requirements",
      "covers" => [
        "feature_scope",
        "user_types",
        "core_functionality",
        "data_entities",
        "integrations",
        "business_rules",
        "constraints"
      ],
      "required_outputs" => ["requirements", "acceptance_criteria", "open_questions"]
    },
    "D2_decomposition" => %{
      "id" => "D2_decomposition",
      "phase" => "decomposition",
      "label" => "D2 Decomposition",
      "covers" => [
        "architecture_pattern",
        "decomposition_strategy",
        "unit_proposals",
        "dependencies",
        "development_sequence"
      ],
      "required_outputs" => ["unit_graph", "blocking_relationships", "parallelizable_units"]
    },
    "D3_design" => %{
      "id" => "D3_design",
      "phase" => "design",
      "label" => "D3 Design",
      "covers" => [
        "technology_stack",
        "frameworks",
        "data_layer",
        "testing_strategy",
        "observability_operations",
        "infrastructure",
        "code_organization"
      ],
      "required_outputs" => ["selected_option", "rejected_options", "implementation_boundaries"]
    },
    "D4_tasks" => %{
      "id" => "D4_tasks",
      "phase" => "tasks",
      "label" => "D4 Tasks",
      "covers" => [
        "breakdown_strategy",
        "implementation_approach",
        "component_priority",
        "integration_strategy",
        "task_granularity"
      ],
      "required_outputs" => ["implementation_steps", "validation_plan", "task_dependencies"]
    },
    "D5_deploy" => %{
      "id" => "D5_deploy",
      "phase" => "deploy",
      "label" => "D5 Deploy",
      "covers" => [
        "ci_cd_platform",
        "deployment_target",
        "deployment_strategy",
        "environments",
        "promotion",
        "secrets_management",
        "iac",
        "rollback",
        "database_migrations",
        "post_deploy_verification"
      ],
      "required_outputs" => ["rollback_plan", "promotion_gate", "post_deploy_checks"]
    }
  }

  def gates, do: Enum.map(@gate_order, &Map.fetch!(@gates, &1))

  def get(id) when is_atom(id), do: get(Atom.to_string(id))

  def get(id) when is_binary(id), do: Map.get(@gates, id)
  def get(_), do: nil

  def normalize_id(nil), do: nil

  def normalize_id(id) when is_atom(id), do: normalize_id(Atom.to_string(id))

  def normalize_id(id) when is_binary(id) do
    cond do
      Map.has_key?(@gates, id) -> id
      Map.has_key?(@gates, String.upcase(id)) -> String.upcase(id)
      true -> gate_id_for_phase(id)
    end
  end

  def normalize_id(_), do: nil

  def gate_id_for_phase(phase) when is_binary(phase) do
    normalized = phase |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")

    # Direct AIDLC phase match (requirements, decomposition, design, tasks, deploy)
    direct =
      Enum.find(@gate_order, fn gate_id ->
        Map.fetch!(@gates, gate_id)["phase"] == normalized or
          String.ends_with?(gate_id, "_" <> normalized)
      end)

    direct || Map.get(@ck_phase_to_gate, normalized)
  end

  def gate_id_for_phase(_), do: nil

  def preset_for_phase(phase) do
    phase
    |> gate_id_for_phase()
    |> get()
  end

  def annotate_refinement(refinement) when is_map(refinement) do
    gate_id =
      normalize_id(refinement["decision_gate"] || refinement["gate"] || refinement["phase"])

    gate = get(gate_id) || preset_for_phase(refinement["phase"])

    if gate do
      refinement
      |> Map.put(
        "decision_gate",
        Map.take(gate, ["id", "phase", "label", "covers", "required_outputs"])
      )
      |> Map.put_new("decision_gate_status", "pending")
    else
      refinement
    end
  end

  def annotate_refinement(refinement), do: refinement

  def review_gate_summary(nil), do: nil

  def review_gate_summary(gate_id) do
    case get(normalize_id(gate_id)) do
      nil -> nil
      gate -> Map.take(gate, ["id", "phase", "label", "covers", "required_outputs"])
    end
  end
end
