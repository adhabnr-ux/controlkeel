defmodule ControlKeel.Skills.PluginTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Skills.Plugin
  alias ControlKeel.Skills.Plugin.Registry

  describe "Registry.all/0" do
    test "returns 8 plugins" do
      assert length(Registry.all()) == 8
    end

    test "every entry has required keys" do
      for plugin <- Registry.all() do
        assert Map.has_key?(plugin, :id)
        assert Map.has_key?(plugin, :label)
        assert Map.has_key?(plugin, :target_id)
        assert Map.has_key?(plugin, :install_path)
        assert Map.has_key?(plugin, :manifest_file)
        assert Map.has_key?(plugin, :description)
      end
    end

    test "no duplicate IDs" do
      ids = Enum.map(Registry.all(), & &1.id)
      assert ids == Enum.uniq(ids)
    end
  end

  describe "Registry.get/1" do
    test "finds plugin by id" do
      assert %{} = Registry.get("codex-plugin")
      assert Registry.get("codex-plugin").label == "Codex plugin bundle"
    end

    test "returns nil for unknown id" do
      assert Registry.get("nonexistent-plugin") == nil
    end
  end

  describe "Registry.ids/0" do
    test "returns all plugin IDs" do
      ids = Registry.ids()
      assert "codex-plugin" in ids
      assert "claude-plugin" in ids
      assert "copilot-plugin" in ids
      assert "opencode-plugin" in ids
    end
  end

  describe "Registry.exists?/1" do
    test "returns true for known plugins" do
      assert Registry.exists?("codex-plugin")
      assert Registry.exists?("claude-plugin")
    end

    test "returns false for unknown plugins" do
      refute Registry.exists?("nonexistent-plugin")
    end
  end

  describe "Registry.count/0" do
    test "returns 8" do
      assert Registry.count() == 8
    end
  end

  describe "Plugin.info/1" do
    test "returns info map for a callback module" do
      info = Plugin.info(ControlKeel.Skills.Plugin.CodexPlugin)
      assert info.id == "codex-plugin"
      assert info.target_id == "codex"
    end
  end

  describe "behaviour conformance" do
    for module <- [
          ControlKeel.Skills.Plugin.CodexPlugin,
          ControlKeel.Skills.Plugin.ClaudePlugin,
          ControlKeel.Skills.Plugin.CopilotPlugin,
          ControlKeel.Skills.Plugin.AugmentPlugin,
          ControlKeel.Skills.Plugin.DroidPlugin,
          ControlKeel.Skills.Plugin.OpenclawPlugin,
          ControlKeel.Skills.Plugin.CursorPlugin,
          ControlKeel.Skills.Plugin.OpencodePlugin
        ] do
      test "#{inspect(module)} implements all callbacks" do
        mod = unquote(module)
        Code.ensure_loaded!(mod)
        assert function_exported?(mod, :id, 0)
        assert function_exported?(mod, :label, 0)
        assert function_exported?(mod, :target_id, 0)
        assert function_exported?(mod, :install_path, 0)
        assert function_exported?(mod, :manifest_file, 0)
        assert function_exported?(mod, :description, 0)
      end
    end
  end

  describe "plugin target_ids reference valid skill targets" do
    test "each plugin target_id exists in SkillTarget catalog" do
      alias ControlKeel.Skills.SkillTarget

      target_ids = SkillTarget.ids()

      for plugin <- Registry.all() do
        assert plugin.target_id in target_ids,
               "Plugin #{plugin.id} references unknown target_id: #{plugin.target_id}"
      end
    end
  end
end
