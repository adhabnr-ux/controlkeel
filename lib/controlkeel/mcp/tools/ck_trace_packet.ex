defmodule ControlKeel.MCP.Tools.CkTracePacket do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, events_limit} <- optional_integer(arguments, "events_limit", 25) do
      Mission.trace_improvement_packet(session_id,
        task_id: task_id,
        events_limit: events_limit
      )
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
