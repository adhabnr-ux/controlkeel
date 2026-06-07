defmodule ControlKeel.Skills.Exporter.Shared do
  @moduledoc false

  # Resolve the hook script from whichever scope actually installed it: project
  # scope writes scripts under the repo root, user scope writes them under $HOME.
  # A user-scoped attach (claude-code's default) lands hooks in $HOME/.claude/hooks
  # while the settings live in $HOME/.claude/settings.json, so a project-only
  # "$root/#{relative_path}" reference would miss them and exit 127. Try the
  # project root first, then $HOME, and no-op silently if neither has the script.
  def repo_hook_command(relative_path) do
    "sh -c 'root=${CK_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}; for d in \"$root\" \"$HOME\"; do [ -f \"$d/#{relative_path}\" ] && exec sh \"$d/#{relative_path}\"; done; exit 0'"
  end

  def global_hook_command(relative_path) do
    "sh -c 'exec sh \"$HOME/#{relative_path}\"'"
  end
end
