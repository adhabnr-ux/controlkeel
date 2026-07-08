defmodule ControlKeel.MCP.Tools.CkSkillEvolution do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, session_limit} <- optional_integer(arguments, "session_limit", 5),
         {:ok, same_domain_only} <-
           Arguments.optional_boolean(arguments, "same_domain_only", true),
         {:ok, install} <- Arguments.optional_boolean(arguments, "install", false),
         {:ok, validate_only} <- Arguments.optional_boolean(arguments, "validate_only", false) do
      opts =
        [
          session_limit: session_limit,
          same_domain_only: same_domain_only,
          current_skill_name: Map.get(arguments, "current_skill_name", "trace-evolved-skill"),
          current_skill_content: Map.get(arguments, "current_skill_content", ""),
          project_root: Arguments.project_root(arguments)
        ]

      cond do
        install ->
          with {:ok, result} <- Mission.apply_skill_evolution(session_id, opts) do
            {:ok, result}
          end

        validate_only ->
          with {:ok, verdict} <- Mission.validate_skill_evolution(session_id, opts) do
            {:ok, verdict}
          end

        true ->
          with {:ok, packet} <- Mission.skill_evolution_packet(session_id, opts) do
            {:ok, packet}
          end
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value -> Arguments.normalize_integer(value, key)
    end
  end
end
