defmodule ControlKeel.RuntimeConformanceTest do
  @moduledoc false
  # Cross-runtime conformance test matrix for P2-10.
  # Asserts parity across codex, claude, cursor, opencode, t3code
  # for capabilities, approvals, session support, and event emission.

  use ExUnit.Case, async: true

  alias ControlKeel.AgentIntegration
  alias ControlKeel.MCP.Protocol
  alias ControlKeel.ProtocolInterop

  @attach_clients ["claude-code", "codex-cli", "codex-app-server", "opencode", "t3code"]

  describe "all attach_client runtimes expose required struct fields" do
    for agent_id <- @attach_clients do
      test "#{agent_id} has non-empty runtime_capabilities" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert integration != nil
        assert integration.support_class == "attach_client"
        assert is_map(integration.runtime_capabilities)
        assert map_size(integration.runtime_capabilities) > 0
      end

      test "#{agent_id} has runtime_transport" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert is_binary(integration.runtime_transport)
        assert String.length(integration.runtime_transport) > 0
      end

      test "#{agent_id} has runtime_review_transport" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert is_binary(integration.runtime_review_transport)
        assert String.length(integration.runtime_review_transport) > 0
      end

      test "#{agent_id} has runtime_session_support map" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert is_map(integration.runtime_session_support)
        assert Map.has_key?(integration.runtime_session_support, "create")
        assert Map.has_key?(integration.runtime_session_support, "fork")
        assert Map.has_key?(integration.runtime_session_support, "resume")
        assert Map.has_key?(integration.runtime_session_support, "streaming")
      end

      test "#{agent_id} capability map has all 5 required keys" do
        integration = AgentIntegration.get(unquote(agent_id))
        caps = integration.runtime_capabilities

        assert Map.has_key?(caps, :policy_gate)
        assert Map.has_key?(caps, :tool_approval)
        assert Map.has_key?(caps, :user_input_pause_resume)
        assert Map.has_key?(caps, :deterministic_event_ids)
        assert Map.has_key?(caps, :replay_safe_delivery)
      end

      test "#{agent_id} has valid submission/feedback/phase modes" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert integration.submission_mode in [
                 "tool_call",
                 "hook",
                 "command",
                 "file_watch",
                 "manual"
               ]

        assert integration.feedback_mode in ["tool_call", "file_patch", "command_reply", "manual"]
        assert integration.phase_model in ["host_plan_mode", "file_plan_mode", "review_only"]
      end
    end
  end

  describe "policy gate parity" do
    for agent_id <- @attach_clients do
      test "#{agent_id} has policy_gate enabled" do
        integration = AgentIntegration.get(unquote(agent_id))

        assert integration.runtime_capabilities[:policy_gate] == true
      end
    end
  end

  describe "observable contract parity" do
    test "hosted MCP scope map covers every hosted tool schema" do
      hosted_names = ProtocolInterop.hosted_tool_names()

      schema_names =
        Protocol.tool_schemas(tool_names: hosted_names, tool_groups: :all)
        |> Enum.map(& &1["name"])

      assert Enum.sort(schema_names) == Enum.sort(hosted_names)
    end

    test "hosted MCP tool schemas keep object inputs and descriptions" do
      for schema <-
            Protocol.tool_schemas(
              tool_names: ProtocolInterop.hosted_tool_names(),
              tool_groups: :all
            ) do
        assert is_binary(schema["description"])
        assert get_in(schema, ["inputSchema", "type"]) == "object"
        assert is_map(get_in(schema, ["inputSchema", "properties"]))
      end
    end

    test "hosted MCP scopes are explicit for every exposed tool" do
      hosted_scopes = ProtocolInterop.hosted_mcp_scopes()

      assert "mcp:access" in hosted_scopes
      assert "review:write" in hosted_scopes
      assert "review:read" in hosted_scopes
      assert "finding:write" in hosted_scopes
      assert "validate:run" in hosted_scopes
    end

    test "core review and governance tools stay visible as one contract family" do
      hosted_names = ProtocolInterop.hosted_tool_names()

      for tool <-
            ~w(ck_context ck_validate ck_finding ck_review_submit ck_review_status ck_review_feedback ck_budget ck_route ck_delegate) do
        assert tool in hosted_names
      end
    end
  end
end
