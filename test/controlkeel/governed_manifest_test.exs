defmodule ControlKeel.GovernedManifestTest do
  use ExUnit.Case, async: true

  alias ControlKeel.GovernedManifest

  test "builds manifest with active gate and context rehydration packet" do
    manifest =
      GovernedManifest.build(%{
        session_id: 1,
        task_id: 2,
        feature: "checkout",
        scope: "feature",
        phase: "design",
        validation_commands: ["mix test"],
        blocked_findings: ["finding-1"]
      })

    assert manifest["version"] == "1.0.0"
    assert manifest["feature"] == "checkout"
    assert manifest["context_rehydration"]["active_gate"] == "D3_design"
    assert manifest["context_rehydration"]["blocked_findings"] == ["finding-1"]
    assert Enum.any?(manifest["decision_gates"], &(&1["status"] == "active"))
  end
end
