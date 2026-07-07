defmodule ControlKeel.MCP.Tools.CkExperienceRead do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, source_session_id} <- optional_integer(arguments, "source_session_id", session_id),
         {:ok, task_id} <- optional_integer(arguments, "task_id"),
         {:ok, artifact_type} <- Arguments.required_string(arguments, "artifact_type") do
      Mission.experience_history_read(session_id,
        source_session_id: source_session_id,
        task_id: task_id,
        artifact_type: artifact_type
      )
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp optional_integer(arguments, key, default \\ nil) do
    case Map.get(arguments, key, default) do
      nil -> {:ok, nil}
      value -> Arguments.normalize_integer(value, key)
    end
  end
end
