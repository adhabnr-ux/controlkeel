defmodule ControlKeel.MCP.Tools.CkCopilot do
  @moduledoc false

  alias ControlKeel.Governance.CopilotChannel
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Copilot operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    session_id = Arguments.parse_integer(arguments["session_id"])
    mode = Map.get(arguments, "mode", "history")

    case session_id do
      nil ->
        {:error, {:invalid_arguments, "`session_id` is required"}}

      id when is_integer(id) ->
        case mode do
          "subscribe" ->
            CopilotChannel.subscribe(id)
            {:ok, %{"status" => "subscribed", "session_id" => id}}

          "publish" ->
            event_type = arguments["event_type"]
            payload = arguments["payload"] || %{}

            case event_type do
              nil ->
                {:error, {:invalid_arguments, "`event_type` is required for publish mode"}}

              et
              when et in ~w(human.viewing human.editing human.approving human.commenting agent.status agent.progress) ->
                CopilotChannel.publish(id, et, payload,
                  actor: arguments["actor"] || "unknown",
                  task_id: Arguments.parse_integer(arguments["task_id"])
                )

                {:ok, %{"status" => "published", "session_id" => id, "event_type" => et}}

              _ ->
                {:error,
                 {:invalid_arguments,
                  "Invalid event_type. Must be one of: human.viewing, human.editing, human.approving, human.commenting, agent.status, agent.progress"}}
            end

          "presence" ->
            {:ok, CopilotChannel.presence(id)}

          "history" ->
            limit = Arguments.parse_integer(arguments["limit"]) || 50
            {:ok, events} = CopilotChannel.history(id, limit: limit)
            {:ok, %{"events" => Enum.map(events, &format_event/1), "count" => length(events)}}

          _ ->
            {:error,
             {:invalid_arguments, "mode must be subscribe, publish, presence, or history"}}
        end
    end
  end

  defp format_event(event) do
    %{
      "id" => event.id,
      "session_id" => event.session_id,
      "event_type" => event.event_type,
      "actor" => event.actor,
      "task_id" => event.task_id,
      "payload" => event.payload,
      "timestamp" => event.timestamp
    }
  end
end
