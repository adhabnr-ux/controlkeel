defmodule ControlKeel.MCP.Tools.CkCheckpointRestore do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission.WorkspaceCheckpoint

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, checkpoint_id} <- Arguments.required_integer(arguments, "checkpoint_id") do
      strict = Map.get(arguments, "strict", false)
      opts = [strict: strict]

      WorkspaceCheckpoint.restore(session_id, checkpoint_id, opts)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
