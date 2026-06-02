defmodule ControlKeel.Skills.Plugin.CodexPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "codex-plugin"
  def label, do: "Codex plugin bundle"
  def target_id, do: "codex"
  def install_path, do: ".agents/plugins"
  def manifest_file, do: "marketplace.json"

  def description,
    do:
      "Marketplace-ready Codex plugin bundle with skills, agents, hooks, MCP, and marketplace metadata."
end
