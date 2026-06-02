defmodule ControlKeel.Skills.Plugin.CursorPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "cursor-plugin"
  def label, do: "Cursor plugin bundle"
  def target_id, do: "cursor-native"
  def install_path, do: ".cursor/plugins"
  def manifest_file, do: "plugin.json"

  def description,
    do: "Cursor-native plugin bundle with rules, project prompts, and MCP companion config."
end
