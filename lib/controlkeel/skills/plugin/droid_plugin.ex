defmodule ControlKeel.Skills.Plugin.DroidPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "droid-plugin"
  def label, do: "Factory Droid plugin bundle"
  def target_id, do: "droid-bundle"
  def install_path, do: ".factory/plugins"
  def manifest_file, do: "plugin.json"

  def description,
    do:
      "Shareable Factory plugin bundle with plugin manifest, skills, commands, droids, hooks, and MCP config."
end
