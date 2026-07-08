defmodule ControlKeel.Mission.DecisionGatesTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Mission.DecisionGates

  test "exposes D1-D5 gate presets in lifecycle order" do
    gate_ids = DecisionGates.gates() |> Enum.map(& &1["id"])

    assert gate_ids == [
             "D1_requirements",
             "D2_decomposition",
             "D3_design",
             "D4_tasks",
             "D5_deploy"
           ]

    assert DecisionGates.preset_for_phase("design")["id"] == "D3_design"
  end

  test "annotates plan refinement with active decision gate" do
    refinement = DecisionGates.annotate_refinement(%{"phase" => "tasks"})

    assert refinement["decision_gate"]["id"] == "D4_tasks"
    assert "validation_plan" in refinement["decision_gate"]["required_outputs"]
    assert refinement["decision_gate_status"] == "pending"
  end

  test "maps CK plan phases to the closest AIDLC gate" do
    assert DecisionGates.gate_id_for_phase("implementation_plan") == "D4_tasks"
    assert DecisionGates.gate_id_for_phase("code_backed_plan") == "D4_tasks"
    assert DecisionGates.gate_id_for_phase("design_options") == "D3_design"
    assert DecisionGates.gate_id_for_phase("ticket") == "D1_requirements"
    assert DecisionGates.gate_id_for_phase("research_packet") == "D1_requirements"
  end

  test "annotate_refinement works through CK plan phase vocabulary" do
    refinement = DecisionGates.annotate_refinement(%{"phase" => "implementation_plan"})

    assert refinement["decision_gate"]["id"] == "D4_tasks"
    assert refinement["decision_gate_status"] == "pending"
  end
end
