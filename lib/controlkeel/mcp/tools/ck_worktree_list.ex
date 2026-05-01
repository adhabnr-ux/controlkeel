defmodule ControlKeel.MCP.Tools.CkWorktreeList do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.WorkspaceContext

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)
    WorkspaceContext.list_worktrees(project_root)
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
