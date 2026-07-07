defmodule ControlKeel.MCP.Tools.CkFailureClusters do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 5),
         {:ok, same_domain_only} <-
           Arguments.optional_boolean(arguments, "same_domain_only", true) do
      Mission.failure_mode_clusters(session_id,
        session_limit: session_limit,
        same_domain_only: same_domain_only
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
