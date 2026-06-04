defmodule ControlKeel.BenchmarkMetadataTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Benchmark.Metadata

  test "normalizes documented eval metadata fields" do
    metadata =
      Metadata.normalize_scenario_metadata(%{
        "metadata" => %{
          "eval_source" => "production_trace",
          "eval_mode" => "deterministic",
          "failure_dimension" => "groundedness",
          "signal_source" => "trajectory"
        }
      })

    assert metadata["eval_source"] == "production_trace"
    assert metadata["eval_mode"] == "deterministic"
    assert metadata["failure_dimension"] == "groundedness"
    assert metadata["signal_source"] == "trajectory"
  end

  test "drops invalid documented enum values while preserving open metadata" do
    metadata =
      Metadata.normalize_run_metadata(%{
        eval_source: "invented",
        eval_mode: "human_golden",
        signal_source: "self_diagnostic",
        custom_version: "v1"
      })

    refute Map.has_key?(metadata, "eval_source")
    assert metadata["eval_mode"] == "human_golden"
    assert metadata["signal_source"] == "self_diagnostic"
    assert metadata["custom_version"] == "v1"
  end

  test "normalizes documented AgentSpec metadata fields" do
    metadata =
      Metadata.normalize_scenario_metadata(%{
        "metadata" => %{
          agent_spec_id: " support agent v1 ",
          agent_spec_version: " 2026 06 04 ",
          task_spec_id: " refund policy v1 ",
          agent_role: " support agent ",
          task_scope: " Answer refund questions ",
          persona_or_actor_context: " logged-in customer ",
          allowed_actions: [" read_order ", " offer_policy_link ", ""],
          prohibited_actions: ["wire money", 123],
          robustness_requirements: ["typos", "paraphrases"],
          promotion_gates: ["held-out pass"],
          domain_terms: "not-a-list"
        }
      })

    assert metadata["agent_spec_id"] == "support agent v1"
    assert metadata["agent_spec_version"] == "2026 06 04"
    assert metadata["task_spec_id"] == "refund policy v1"
    assert metadata["agent_role"] == "support agent"
    assert metadata["task_scope"] == "Answer refund questions"
    assert metadata["persona_or_actor_context"] == "logged-in customer"
    assert metadata["allowed_actions"] == ["read_order", "offer_policy_link"]
    assert metadata["prohibited_actions"] == ["wire money"]
    assert metadata["robustness_requirements"] == ["typos", "paraphrases"]
    assert metadata["promotion_gates"] == ["held-out pass"]
    refute Map.has_key?(metadata, "domain_terms")
  end

  test "normalizes skill A/B eval metadata fields" do
    metadata =
      Metadata.normalize_scenario_metadata(%{
        "metadata" => %{
          skill_name: " authkit gotchas ",
          skill_variant: " with_skill ",
          baseline_variant: " without_skill ",
          skill_delta_score: " -0.20 ",
          skill_loaded: "true",
          baseline_without_skill: false,
          skill_harmed_performance: true
        }
      })

    assert metadata["skill_name"] == "authkit gotchas"
    assert metadata["skill_variant"] == "with_skill"
    assert metadata["baseline_variant"] == "without_skill"
    assert metadata["skill_delta_score"] == "-0.20"
    assert metadata["skill_loaded"] == true
    assert metadata["baseline_without_skill"] == false
    assert metadata["skill_harmed_performance"] == true
  end

  test "exposes documented metadata vocabularies" do
    assert "red_team" in Metadata.valid_eval_sources()
    assert "llm_judge" in Metadata.valid_eval_modes()
    assert "task_completion" in Metadata.valid_failure_dimensions()
    assert "self_diagnostic" in Metadata.valid_signal_sources()
    assert "agent_spec_id" in Metadata.agent_spec_fields()["string"]
    assert "task_spec_id" in Metadata.agent_spec_fields()["string"]
    assert "allowed_actions" in Metadata.agent_spec_fields()["string_list"]
    assert "skill_name" in Metadata.agent_spec_fields()["skill_eval_string"]
    assert "skill_harmed_performance" in Metadata.agent_spec_fields()["skill_eval_boolean"]
  end
end
