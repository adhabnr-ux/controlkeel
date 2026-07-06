defmodule ControlKeel.MCP.Tools.CkFsLs do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Project.VirtualWorkspace

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments) do
      VirtualWorkspace.list(session_id, Map.get(arguments, "path", "."))
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
