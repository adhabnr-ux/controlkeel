defmodule ControlKeel.MCP.Tools.CkTracePacket do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, events_limit} <- optional_integer(arguments, "events_limit", 25) do
      Mission.trace_improvement_packet(session_id,
        task_id: task_id,
        events_limit: events_limit
      )
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default \\ nil) do
    case Map.get(arguments, key, default) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
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
end
