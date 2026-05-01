defmodule ControlKeel.MCP.Tools.CkGitCommit do
  @moduledoc false

  alias ControlKeel.GitWorkflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)
    message = Map.get(arguments, "message")

    if is_nil(message) or message == "" do
      {:error, {:invalid_arguments, "`message` is required"}}
    else
      opts = []

      opts =
        if Map.has_key?(arguments, "session_id"),
          do: [{:session_id, Map.get(arguments, "session_id")} | opts],
          else: opts

      GitWorkflow.commit(project_root, message, opts)
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
