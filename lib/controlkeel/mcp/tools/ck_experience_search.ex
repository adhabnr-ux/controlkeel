defmodule ControlKeel.MCP.Tools.CkExperienceSearch do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  @max_limit 20

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session} <- fetch_session(session_id),
         {:ok, query} <- required_string(arguments, "query"),
         {:ok, limit} <- optional_integer(arguments, "limit", 10),
         :ok <- validate_limit(limit) do
      Mission.experience_search(session.workspace_id, query, limit: limit)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp fetch_session(session_id) do
    case Mission.get_session(session_id) do
      nil -> {:error, {:invalid_arguments, "Session not found"}}
      session -> {:ok, session}
    end
  end

  defp required_string(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`#{key}` is required and must be a non-empty string"}}
    end
  end

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key) do
      nil ->
        {:ok, default}

      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
        end

      _ ->
        {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp validate_limit(limit) when limit > 0 and limit <= @max_limit, do: :ok

  defp validate_limit(_),
    do: {:error, {:invalid_arguments, "`limit` must be between 1 and #{@max_limit}"}}
end
