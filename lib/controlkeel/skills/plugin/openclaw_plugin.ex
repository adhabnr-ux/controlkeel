defmodule ControlKeel.Skills.Plugin.OpenclawPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "openclaw-plugin"
  def label, do: "OpenClaw plugin bundle"
  def target_id, do: "openclaw-native"
  def install_path, do: ".openclaw/plugins"
  def manifest_file, do: "plugin.json"

  def description,
    do: "Plugin-ready OpenClaw bundle with skills, manifest, and MCP companion config."
end
