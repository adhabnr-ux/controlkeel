defmodule ControlKeel.MCP.Tools.CkCheckpointList do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission.WorkspaceCheckpoint

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, limit} <- Arguments.optional_integer(arguments, "limit") do
      type = Map.get(arguments, "type")

      opts = []
      opts = if type, do: [{:type, type} | opts], else: opts
      opts = if limit, do: [{:limit, limit} | opts], else: opts

      WorkspaceCheckpoint.list(session_id, opts)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
