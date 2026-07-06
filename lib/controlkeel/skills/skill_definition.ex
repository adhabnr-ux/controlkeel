defmodule ControlKeel.Skills.SkillDefinition do
  @moduledoc false

  defstruct [
    :name,
    :description,
    :path,
    :skill_dir,
    :body,
    :metadata,
    :scope,
    :source,
    :license,
    :compatibility,
    :compatibility_targets,
    :allowed_tools,
    :disallowed_tools,
    :required_mcp_tools,
    :disable_model_invocation,
    :user_invocable,
    :context,
    :agent,
    :paths,
    :hooks,
    :model,
    :effort,
    :shell,
    :resources,
    :diagnostics,
    :openai,
    :agent_metadata,
    :install_state,
    :owner,
    :content_hash,
    :result_schema
  ]
end
