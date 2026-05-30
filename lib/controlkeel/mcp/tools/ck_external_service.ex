defmodule ControlKeel.MCP.Tools.CkExternalService do
  @moduledoc false

  alias ControlKeel.Governance.ExternalServiceTracker

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "External service operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    session_id = normalize_integer(arguments["session_id"])
    mode = Map.get(arguments, "mode", "summary")

    case session_id do
      nil ->
        {:error, {:invalid_arguments, "`session_id` is required"}}

      id when is_integer(id) ->
        case mode do
          "record" ->
            attrs = %{
              session_id: id,
              task_id: normalize_integer(arguments["task_id"]),
              service_name: arguments["service_name"],
              interaction_type: arguments["interaction_type"] || "api_call",
              method: arguments["method"],
              endpoint: arguments["endpoint"],
              status_code: normalize_integer(arguments["status_code"]),
              request_size_bytes: normalize_integer(arguments["request_size_bytes"]) || 0,
              response_size_bytes: normalize_integer(arguments["response_size_bytes"]) || 0,
              latency_ms: normalize_integer(arguments["latency_ms"]),
              tokens_used: normalize_integer(arguments["tokens_used"]) || 0,
              cost_cents: normalize_integer(arguments["cost_cents"]) || 0,
              metadata: arguments["metadata"] || %{}
            }

            case ExternalServiceTracker.record(attrs) do
              {:ok, interaction} -> {:ok, format_interaction(interaction)}
              {:error, changeset} -> {:error, {:invalid_arguments, format_errors(changeset)}}
            end

          "summary" ->
            {:ok, ExternalServiceTracker.summary(id)}

          "rate_limit_status" ->
            {:ok, ExternalServiceTracker.rate_limit_status(id)}

          "top_services" ->
            limit = normalize_integer(arguments["limit"]) || 10
            services = ExternalServiceTracker.top_services(id, limit: limit)
            {:ok, %{"services" => services, "count" => length(services)}}

          _ ->
            {:error,
             {:invalid_arguments,
              "mode must be record, summary, rate_limit_status, or top_services"}}
        end
    end
  end

  defp format_interaction(interaction) do
    %{
      "id" => interaction.id,
      "session_id" => interaction.session_id,
      "task_id" => interaction.task_id,
      "service_name" => interaction.service_name,
      "interaction_type" => interaction.interaction_type,
      "method" => interaction.method,
      "endpoint" => interaction.endpoint,
      "status_code" => interaction.status_code,
      "latency_ms" => interaction.latency_ms,
      "cost_cents" => interaction.cost_cents,
      "redacted" => interaction.redacted
    }
  end

  defp format_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field}: #{msg}" end)
    |> Enum.join("; ")
  end

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end
end
