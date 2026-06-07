defmodule ControlKeel.ExecutionSandbox.PreflightTest do
  use ControlKeel.DataCase, async: true

  import ControlKeel.MissionFixtures

  alias ControlKeel.ExecutionSandbox.Preflight

  describe "check/3" do
    test "proceeds when session_id is nil (backward compatible)" do
      assert {:ok, :proceed} = Preflight.check(nil, ["bash"])
    end

    test "proceeds when no trust boundary findings exist for the session" do
      session = session_fixture()
      assert {:ok, :proceed} = Preflight.check(session.id, ["bash"])
    end

    test "proceeds when only low/medium trust boundary findings exist" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "medium",
        rule_id: "security.trust_boundary.untrusted_instruction_content"
      })

      assert {:ok, :proceed} = Preflight.check(session.id, ["bash"])
    end

    test "blocks when critical trust boundary findings exist" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "critical",
        rule_id: "security.trust_boundary.hidden_instruction_channel"
      })

      assert {:error, {:blocked, reason, findings}} =
               Preflight.check(session.id, ["bash"])

      assert reason =~ "Critical trust boundary findings"
      assert length(findings) == 1
    end

    test "blocks critical findings even with force: true" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "critical",
        rule_id: "security.trust_boundary.untrusted_skill_instruction"
      })

      assert {:error, {:blocked, _reason, _findings}} =
               Preflight.check(session.id, ["bash"], force: true)
    end

    test "warns when high trust boundary findings exist without force" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "high",
        rule_id: "security.trust_boundary.agent_targeted_content_branching"
      })

      assert {:warn, message, findings} = Preflight.check(session.id, ["bash"])
      assert message =~ "High trust boundary findings"
      assert length(findings) == 1
    end

    test "proceeds when high findings exist and force: true" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "high",
        rule_id: "security.trust_boundary.encoded_payload_marker"
      })

      assert {:ok, :proceed} = Preflight.check(session.id, ["bash"], force: true)
    end

    test "ignores non-trust-boundary findings" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "critical",
        rule_id: "security.secrets.hardcoded_secret"
      })

      assert {:ok, :proceed} = Preflight.check(session.id, ["bash"])
    end

    test "filters findings by capability overlap" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "critical",
        rule_id: "security.trust_boundary.high_impact_action_from_untrusted_context",
        metadata: %{"requested_capabilities" => ["deploy", "secrets"]}
      })

      assert {:ok, :proceed} = Preflight.check(session.id, ["bash", "file_read"])
      assert {:error, {:blocked, _, _}} = Preflight.check(session.id, ["deploy"])
    end

    test "matches findings with no capability metadata against any request" do
      session = session_fixture()

      finding_fixture(%{
        session_id: session.id,
        severity: "high",
        rule_id: "security.trust_boundary.agent_targeted_content_branching",
        metadata: %{}
      })

      assert {:warn, _, _} = Preflight.check(session.id, ["bash"])
    end
  end
end
