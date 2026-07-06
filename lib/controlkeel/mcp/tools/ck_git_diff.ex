defmodule ControlKeel.MCP.Tools.CkGitDiff do
  @moduledoc false

  alias ControlKeel.Git.Workflow
  alias ControlKeel.MCP.Arguments

  def call(arguments) when is_map(arguments) do
    project_root = Arguments.project_root(arguments)
    base_ref = optional_ref(arguments, "base_ref")
    head_ref = optional_ref(arguments, "head_ref")

    opts = []

    opts =
      if Map.has_key?(arguments, "session_id"),
        do: [{:session_id, Map.get(arguments, "session_id")} | opts],
        else: opts

    Workflow.diff(project_root, base_ref, head_ref, opts)
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_ref(arguments, key) do
    case Map.get(arguments, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          ref -> ref
        end

      value ->
        value
    end
  end
end
