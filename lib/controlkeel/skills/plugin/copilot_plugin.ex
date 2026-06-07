defmodule ControlKeel.Skills.Plugin.CopilotPlugin do
  @behaviour ControlKeel.Skills.Plugin

  def id, do: "copilot-plugin"
  def label, do: "Copilot / VS Code plugin bundle"
  def target_id, do: "github-repo"
  def install_path, do: ".github/plugins"
  def manifest_file, do: "manifest.json"
  def description, do: "Plugin bundle for GitHub Copilot CLI and VS Code agent mode."
end
