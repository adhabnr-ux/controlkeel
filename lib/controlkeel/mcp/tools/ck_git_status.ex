defmodule ControlKeel.MCP.Tools.CkGitStatus do
  @moduledoc false

  alias ControlKeel.Git.Workflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)

    opts = []

    opts =
      if Map.has_key?(arguments, "session_id"),
        do: [{:session_id, Map.get(arguments, "session_id")} | opts],
        else: opts

    Workflow.status(project_root, opts)
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
