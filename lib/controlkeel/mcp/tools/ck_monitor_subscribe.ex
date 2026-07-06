defmodule ControlKeel.MCP.Tools.CkMonitorSubscribe do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Observability.RemoteMonitoring

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, subscriber_url} <- validate_subscriber_url(arguments) do
      event_types = Map.get(arguments, "event_types", :all)

      opts = [event_types: event_types]
      RemoteMonitoring.subscribe(session_id, subscriber_url, opts)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp validate_subscriber_url(arguments) do
    case Map.get(arguments, "subscriber_url") do
      nil -> {:error, {:invalid_arguments, "`subscriber_url` is required"}}
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, {:invalid_arguments, "`subscriber_url` must be a string"}}
    end
  end
end
