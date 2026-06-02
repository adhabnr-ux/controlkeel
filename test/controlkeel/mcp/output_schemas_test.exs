defmodule ControlKeel.MCP.OutputSchemasTest do
  use ControlKeel.DataCase

  alias ControlKeel.MCP.OutputSchemas
  alias ControlKeel.MCP.Protocol
  alias ControlKeel.MCP.ToolGroups

  describe "schema_for/1" do
    test "returns a schema for every known tool" do
      for tool_name <- ToolGroups.all_tools() do
        schema = OutputSchemas.schema_for(tool_name)

        assert is_map(schema), "Expected schema for #{tool_name} to be a map"
        assert schema["type"] == "object", "Expected #{tool_name} schema type to be object"
        assert is_map(schema["properties"]), "Expected #{tool_name} schema to have properties map"

        assert map_size(schema["properties"]) > 0,
               "Expected #{tool_name} schema properties to be non-empty"
      end
    end

    test "returns generic schema for unknown tool" do
      schema = OutputSchemas.schema_for("ck_nonexistent_tool")

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "status")
      assert Map.has_key?(schema["properties"], "data")
    end

    test "ck_validate schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_validate")
      props = schema["properties"]

      assert Map.has_key?(props, "allowed")
      assert Map.has_key?(props, "decision")
      assert Map.has_key?(props, "summary")
      assert Map.has_key?(props, "findings")
      assert Map.has_key?(props, "fix_prompts")
      assert Map.has_key?(props, "scanned_at")
      assert Map.has_key?(props, "advisory")
    end

    test "ck_context schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_context")
      props = schema["properties"]

      assert Map.has_key?(props, "session_id")
      assert Map.has_key?(props, "budget_summary")
      assert Map.has_key?(props, "active_findings")
      assert Map.has_key?(props, "proof_summary")
      assert Map.has_key?(props, "workspace_context")
      assert Map.has_key?(props, "detail_level")
    end

    test "ck_context schema matches nullable and object-shaped runtime fields" do
      props = OutputSchemas.schema_for("ck_context")["properties"]

      assert props["attach_advisory"]["type"] == "object"
      assert props["past_patterns"]["type"] == ["object", "array"]
      assert props["proof_summary"]["type"] == ["object", "null"]
      assert props["current_task"]["type"] == ["object", "null"]
      assert props["workspace_cache_key"]["type"] == ["string", "null"]
    end

    test "ck_validate schema allows nullable scanner fields" do
      props = OutputSchemas.schema_for("ck_validate")["properties"]
      finding_props = get_in(props, ["findings", "items", "properties"])

      assert props["advisory"]["type"] == ["string", "null"]
      assert props["trust_policy_advisory"]["type"] == ["string", "null"]
      assert finding_props["id"]["type"] == ["string", "null"]
      assert finding_props["location"]["type"] == ["string", "null"]
    end

    test "ck_finding schema allows nullable relationship fields" do
      props = OutputSchemas.schema_for("ck_finding")["properties"]

      assert props["extends_finding_id"]["type"] == ["integer", "null"]
      assert props["contradicts_finding_id"]["type"] == ["integer", "null"]
    end

    test "ck_finding schema has specific properties" do
      schema = OutputSchemas.schema_for("ck_finding")
      props = schema["properties"]

      assert Map.has_key?(props, "finding_id")
      assert Map.has_key?(props, "status")
      assert Map.has_key?(props, "requires_human")
      assert Map.has_key?(props, "resolved_findings_count")
      assert Map.has_key?(props, "summary")
    end
  end

  describe "inject/1" do
    test "injects outputSchema into a tool definition" do
      tool_def = %{"name" => "ck_validate", "description" => "test", "inputSchema" => %{}}
      result = OutputSchemas.inject(tool_def)

      assert Map.has_key?(result, "outputSchema")
      assert result["outputSchema"]["type"] == "object"
      assert Map.has_key?(result["outputSchema"]["properties"], "allowed")
    end

    test "preserves existing keys" do
      tool_def = %{"name" => "ck_route", "description" => "test", "inputSchema" => %{}}
      result = OutputSchemas.inject(tool_def)

      assert result["name"] == "ck_route"
      assert result["description"] == "test"
      assert Map.has_key?(result, "inputSchema")
      assert Map.has_key?(result, "outputSchema")
    end
  end

  describe "tools/list output schema integration" do
    test "all tools returned by tools/list have outputSchema" do
      response =
        Protocol.handle_request(
          %{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "tools/list"
          },
          tool_groups: :all
        )

      assert %{"result" => %{"tools" => tools}} = response
      assert length(tools) > 0

      for tool <- tools do
        name = tool["name"]

        assert Map.has_key?(tool, "outputSchema"),
               "Tool #{name} is missing outputSchema"

        schema = tool["outputSchema"]

        assert schema["type"] == "object",
               "Tool #{name} outputSchema type should be 'object', got: #{inspect(schema["type"])}"

        assert is_map(schema["properties"]),
               "Tool #{name} outputSchema should have properties map"

        assert map_size(schema["properties"]) > 0,
               "Tool #{name} outputSchema properties should not be empty"
      end
    end

    test "all 56 tools have output schema definitions" do
      all_tools = ToolGroups.all_tools()
      schema_tools = OutputSchemas.tool_names()

      for tool_name <- all_tools do
        assert tool_name in schema_tools,
               "Tool #{tool_name} missing from OutputSchemas"
      end

      assert length(all_tools) == 56
      assert length(schema_tools) >= 56
    end
  end
end
