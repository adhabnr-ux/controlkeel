defmodule ControlKeel.MCP.Tools.CkCheckpointCreate do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.WorkspaceCheckpoint

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, task_id} <- Arguments.required_integer(arguments, "task_id") do
      type = Map.get(arguments, "type", "workspace_snapshot")
      summary = Map.get(arguments, "summary", "Workspace checkpoint")
      created_by = Map.get(arguments, "created_by", "system")

      opts = [
        type: type,
        summary: summary,
        created_by: created_by
      ]

      WorkspaceCheckpoint.create(session_id, task_id, opts)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
