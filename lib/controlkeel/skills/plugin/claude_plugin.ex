defmodule ControlKeel.Skills.Plugin.ClaudePlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "claude-plugin"
  def label, do: "Claude plugin bundle"
  def target_id, do: "claude-standalone"
  def install_path, do: ".claude/plugins"
  def manifest_file, do: "plugin.json"
  def description, do: "Marketplace-ready Claude Code plugin bundle with skills, agents, and MCP."
end
