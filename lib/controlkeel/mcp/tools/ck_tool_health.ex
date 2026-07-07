defmodule ControlKeel.MCP.Tools.CkToolHealth do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 10) do
      Mission.governance_coverage(session_id, session_limit: session_limit)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      nil -> {:ok, nil}
      value -> Arguments.normalize_integer(value, key)
    end
  end
end
