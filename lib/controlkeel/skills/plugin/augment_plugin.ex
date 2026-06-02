defmodule ControlKeel.Skills.Plugin.AugmentPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "augment-plugin"
  def label, do: "Augment plugin bundle"
  def target_id, do: "augment-native"
  def install_path, do: ".augment/plugins"
  def manifest_file, do: "plugin.json"

  def description,
    do: "Local Auggie plugin bundle with hooks, agents, commands, rules, skills, and MCP bridge."
end
