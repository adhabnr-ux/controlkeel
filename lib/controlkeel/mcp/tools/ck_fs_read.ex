defmodule ControlKeel.MCP.Tools.CkFsRead do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Project.VirtualWorkspace

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, path} <- Arguments.required_binary(arguments, "path"),
         {:ok, start_line} <- optional_integer(arguments, "start_line", 1),
         {:ok, max_lines} <- optional_integer(arguments, "max_lines", 400) do
      VirtualWorkspace.read(session_id, path,
        start_line: start_line,
        max_lines: max_lines,
        fallback_root: Map.get(arguments, "project_root")
      )
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value -> Arguments.normalize_integer(value, key)
    end
  end
end
