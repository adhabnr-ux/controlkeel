defmodule ControlKeel.MCP.Tools.CkEngineerMirror do
  @moduledoc false

  alias ControlKeel.Learning.EngineerMirror

  def call(arguments) when is_map(arguments) do
    case Map.get(arguments, "session_id") do
      nil ->
        {:error, {:invalid_arguments, "`session_id` is required"}}

      sid when is_integer(sid) ->
        {:ok, EngineerMirror.build(sid)}

      sid when is_binary(sid) ->
        case Integer.parse(sid) do
          {n, ""} -> {:ok, EngineerMirror.build(n)}
          _ -> {:error, {:invalid_arguments, "`session_id` must be an integer"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`session_id` must be an integer"}}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
