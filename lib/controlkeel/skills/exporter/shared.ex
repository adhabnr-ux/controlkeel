defmodule ControlKeel.Skills.Exporter.Shared do
  @moduledoc false

  def repo_hook_command(relative_path) do
    "sh -c 'root=${CK_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}; exec sh \"$root/#{relative_path}\"'"
  end

  def global_hook_command(relative_path) do
    "sh -c 'exec sh \"$HOME/#{relative_path}\"'"
  end
end
