defmodule ControlKeel.MCP.Tools.CkGitDiff do
  @moduledoc false

  alias ControlKeel.GitWorkflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)
    base_ref = Map.get(arguments, "base_ref", "HEAD~1")
    head_ref = Map.get(arguments, "head_ref", "HEAD")

    opts = []

    opts =
      if Map.has_key?(arguments, "session_id"),
        do: [{:session_id, Map.get(arguments, "session_id")} | opts],
        else: opts

    GitWorkflow.diff(project_root, base_ref, head_ref, opts)
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}
end
