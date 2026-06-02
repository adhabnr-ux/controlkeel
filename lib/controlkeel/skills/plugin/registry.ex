defmodule ControlKeel.Skills.Plugin.Registry do
  @moduledoc false

  alias ControlKeel.Skills.Plugin

  @plugins [
    ControlKeel.Skills.Plugin.CodexPlugin,
    ControlKeel.Skills.Plugin.ClaudePlugin,
    ControlKeel.Skills.Plugin.CopilotPlugin,
    ControlKeel.Skills.Plugin.AugmentPlugin,
    ControlKeel.Skills.Plugin.DroidPlugin,
    ControlKeel.Skills.Plugin.OpenclawPlugin,
    ControlKeel.Skills.Plugin.CursorPlugin,
    ControlKeel.Skills.Plugin.OpencodePlugin
  ]

  def all, do: Enum.map(@plugins, &Plugin.info/1)
  def ids, do: Enum.map(@plugins, & &1.id())
  def count, do: length(@plugins)
  def get(id), do: Enum.find(all(), &(&1.id == id))
  def exists?(id), do: id in ids()
end
