defmodule ControlKeel.MCP.Tools.CkFsGrep do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Project.VirtualWorkspace

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, query} <- Arguments.required_binary(arguments, "query"),
         {:ok, limit} <- optional_integer(arguments, "limit", 50),
         {:ok, ignore_case} <- Arguments.optional_boolean(arguments, "ignore_case", false),
         {:ok, fixed_strings} <- Arguments.optional_boolean(arguments, "fixed_strings", true) do
      VirtualWorkspace.grep(session_id, query,
        path: Map.get(arguments, "path", "."),
        limit: limit,
        ignore_case: ignore_case,
        fixed_strings: fixed_strings
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
