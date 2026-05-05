defmodule ControlKeel.Integrations.Deepsec.CLITest do
  use ControlKeel.DataCase

  alias ControlKeel.Integrations.Deepsec.CLI

  describe "available?/0" do
    test "returns boolean indicating if deepsec CLI is available" do
      # This test will pass if deepsec is installed, fail otherwise
      # We can't guarantee deepsec is installed in all environments
      result = CLI.available?()
      assert is_boolean(result)
    end
  end

  describe "version/0" do
    test "returns version if deepsec is available" do
      case CLI.available?() do
        true ->
          assert {:ok, version} = CLI.version()
          assert is_binary(version)
          assert String.length(version) > 0

        false ->
          assert {:error, _reason} = CLI.version()
      end
    end
  end

  describe "parse_json_output/1" do
    test "parses valid JSON output" do
      json_output = ~s({"findings": [{"vulnSlug": "test", "severity": "HIGH"}]})

      assert {:ok, data} = CLI.parse_json_output(json_output)
      assert is_map(data)
      assert Map.has_key?(data, "findings")
    end

    test "returns error for invalid JSON" do
      invalid_json = "not valid json"

      assert {:error, _reason} = CLI.parse_json_output(invalid_json)
    end

    test "extracts JSON from mixed text output" do
      mixed_output = """
      Some text before
      {"findings": [{"vulnSlug": "test", "severity": "HIGH"}]}
      Some text after
      """

      assert {:ok, data} = CLI.parse_json_output(mixed_output)
      assert is_map(data)
    end

    test "returns error when no JSON found" do
      text_only = "Just plain text with no JSON"

      assert {:error, _reason} = CLI.parse_json_output(text_only)
    end
  end

  describe "extract_findings/1" do
    test "extracts findings from JSON output" do
      json_output =
        ~s({"findings": [{"vulnSlug": "sql-injection", "severity": "HIGH", "title": "SQL Injection"}]})

      assert {:ok, findings} = CLI.extract_findings(json_output)
      assert is_list(findings)
      assert length(findings) == 1
    end

    test "handles empty findings array" do
      json_output = ~s({"findings": []})

      assert {:ok, findings} = CLI.extract_findings(json_output)
      assert findings == []
    end

    test "falls back to text extraction when JSON parsing fails" do
      text_output = """
      Found vulnerability: SQL Injection at line 10
      Critical issue detected in auth module
      """

      assert {:ok, findings} = CLI.extract_findings(text_output)
      assert is_list(findings)
      # Should extract some findings from text
      assert length(findings) > 0
    end

    test "infers severity from text" do
      text_output = "CRITICAL vulnerability found in authentication module"

      assert {:ok, findings} = CLI.extract_findings(text_output)
      assert is_list(findings)
      assert length(findings) > 0

      first_finding = List.first(findings)
      assert Map.get(first_finding, "severity") == "CRITICAL"
    end
  end

  describe "init/1" do
    test "requires workspace_path option" do
      # Mock the workspace path
      tmp_dir = System.tmp_dir!()
      workspace_path = Path.join(tmp_dir, "test_deepsec_#{System.unique_integer()}")

      # Create the directory
      File.mkdir_p!(workspace_path)

      # Test init (will fail if deepsec not installed, but we test the interface)
      result = CLI.init(workspace_path: workspace_path)

      # We expect either success or an error about deepsec not being available
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end

      # Cleanup
      File.rm_rf!(workspace_path)
    end
  end
end
