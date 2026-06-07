defmodule ControlKeel.Skills.Plugin.OpencodePlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "opencode-plugin"
  def label, do: "OpenCode npm plugin"
  def target_id, do: "opencode-native"
  def install_path, do: ".opencode/plugins"
  def manifest_file, do: "package.json"

  def description,
    do: "OpenCode-native plugins, agents, commands, MCP config, and governance instructions."
end
