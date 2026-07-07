defmodule ControlKeel.MCP.Tools.CkAttachTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Tools.CkAttach

  describe "argument validation" do
    test "rejects missing host" do
      assert {:error, {:invalid_arguments, message}} = CkAttach.call(%{})
      assert message =~ "host is required"
    end

    test "rejects non-object arguments" do
      assert {:error, {:invalid_arguments, _}} = CkAttach.call("not a map")
    end

    test "rejects unknown host with helpful message" do
      assert {:error, {:invalid_arguments, message}} = CkAttach.call(%{"host" => "vim"})
      assert message =~ "unknown host: vim"
      assert message =~ "claude-code"
    end

    test "rejects empty host string" do
      assert {:error, {:invalid_arguments, _}} = CkAttach.call(%{"host" => ""})
    end
  end
end
