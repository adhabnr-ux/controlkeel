defmodule ControlKeel.MCP.Tools.CkExperienceIndex do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 10),
         {:ok, same_domain_only} <- optional_boolean(arguments, "same_domain_only", true),
         {:ok, query} <- optional_string(arguments, "query") do
      Mission.experience_history_index(session_id,
        session_limit: session_limit,
        same_domain_only: same_domain_only,
        query: query
      )
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value -> normalize_integer(value, key)
    end
  end

  defp optional_boolean(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value when is_boolean(value) -> {:ok, value}
      nil -> {:ok, default}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a boolean if provided"}}
    end
  end

  defp normalize_integer(value, _key) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value, key) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}
    end
  end

  defp normalize_integer(_value, key),
    do: {:error, {:invalid_arguments, "`#{key}` must be an integer if provided"}}

  defp optional_string(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a string if provided"}}
    end
  end
end
