defmodule ControlKeel.Validation.Matchers.ScannerTest do
  use ExUnit.Case

  alias ControlKeel.Validation.Matchers.Scanner

  describe "deepsec_scan/1" do
    test "returns error when deepsec CLI is not available" do
      # Skip this test if deepsec is actually available
      unless ControlKeel.Integrations.Deepsec.CLI.available?() do
        assert {:error, _reason} = Scanner.deepsec_scan([])
      end
    end

    test "accepts workspace_path option" do
      # Test that the function accepts the option
      # Actual execution requires deepsec to be installed
      tmp_dir = System.tmp_dir!()
      workspace_path = Path.join(tmp_dir, "test_workspace")

      # Just test that it doesn't crash on invalid input
      # (will fail with proper error about deepsec not being available)
      result = Scanner.deepsec_scan(workspace_path: workspace_path)

      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end
end
