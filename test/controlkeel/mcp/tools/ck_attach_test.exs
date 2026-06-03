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

  describe "attachable_hosts/0" do
    test "lists the supported host IDs" do
      hosts = CkAttach.attachable_hosts()

      assert "claude-code" in hosts
      assert "cursor" in hosts
      assert "codex-cli" in hosts
      assert "opencode" in hosts
      assert "copilot" in hosts
      assert length(hosts) >= 15
    end

    test "stays in sync with the AgentIntegration attach-client set (no drift below the CLI)" do
      hosts = CkAttach.attachable_hosts()

      # These hosts are attachable by the CLI but were rejected by the old hardcoded
      # 17-host allowlist; ck_attach now derives the set from the single source of truth.
      assert "amp" in hosts
      assert "warp" in hosts
      assert hosts == ControlKeel.AgentIntegration.attachable_ids()
    end
  end
end
