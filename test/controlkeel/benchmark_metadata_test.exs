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

  test "exposes documented metadata vocabularies" do
    assert "red_team" in Metadata.valid_eval_sources()
    assert "llm_judge" in Metadata.valid_eval_modes()
    assert "task_completion" in Metadata.valid_failure_dimensions()
    assert "self_diagnostic" in Metadata.valid_signal_sources()
  end
end
