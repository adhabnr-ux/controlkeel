defmodule ControlKeel.Intent.ExecutionPostureTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Intent

  import ControlKeel.IntentFixtures

  test "prefers typed runtime for regulated or critical briefs" do
    brief = execution_brief_fixture()
    posture = Intent.execution_posture(brief)

    assert posture["exploration_surface"] == "virtual_workspace"
    assert posture["state_surface"] == "typed_storage"
    assert posture["api_execution_surface"] == "typed_runtime"
    assert posture["mutation_surface"] == "shell_sandbox"
    assert posture["shell_role"] == "broad_fallback_only"
    assert posture["clearance_focus"] == ["bash", "file_write", "network", "deploy", "secrets"]
  end

  test "keeps lower-risk software briefs hybrid while preserving read-only discovery" do
    brief =
      execution_brief_fixture(
        payload: %{
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "Source code and test fixtures only.",
          "recommended_stack" => "Phoenix monolith with repo-local tests"
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software"
        }
      )

    posture = Intent.execution_posture(brief)

    assert posture["exploration_surface"] == "virtual_workspace"
    assert posture["state_surface"] == "typed_storage"
    assert posture["api_execution_surface"] == "typed_runtime_or_shell"
    assert posture["shell_role"] == "repo_local_fallback"
    assert posture["clearance_focus"] == ["file_write", "network", "deploy", "secrets"]
    refute Map.has_key?(posture, "code_mode_policy")
  end

  test "recommends code_mode_policy when the brief emphasizes typed integration discovery" do
    brief =
      execution_brief_fixture(
        payload: %{
          "project_name" => "API Control Plane",
          "idea" =>
            "Use a search and execute code-mode workflow to inspect an OpenAPI spec, then run a single-shot orchestration against matching endpoints.",
          "domain_pack" => "software",
          "occupation" => "Software",
          "risk_tier" => "moderate",
          "compliance" => [],
          "data_summary" => "OpenAPI schema and API responses only.",
          "recommended_stack" => "Typed runtime with code-mode search+execute adapter"
        },
        compiler: %{
          "occupation" => "software",
          "domain_pack" => "software",
          "provider" => "openai",
          "interview_answers" => %{
            "constraints" => "Use code-mode search execute flow for API orchestration"
          }
        }
      )

    posture = Intent.execution_posture(brief)

    assert posture["code_mode_policy"]["sandbox_required"] == true

    assert posture["code_mode_policy"]["default_denied_capabilities"] == [
             "filesystem",
             "network",
             "secrets",
             "shell",
             "deploy"
           ]
  end
end
