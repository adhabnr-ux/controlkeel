defmodule ControlKeel.Agent.Runtimes.Registry do
  @moduledoc false

  alias ControlKeel.Agent.Integration

  @modules [
    ControlKeel.Agent.Runtimes.Augment,
    ControlKeel.Agent.Runtimes.ClaudeCode,
    ControlKeel.Agent.Runtimes.CodexAppServer,
    ControlKeel.Agent.Runtimes.CodexCLI,
    ControlKeel.Agent.Runtimes.Copilot,
    ControlKeel.Agent.Runtimes.OpenCode,
    ControlKeel.Agent.Runtimes.T3Code,
    ControlKeel.Agent.Runtimes.Pi,
    ControlKeel.Agent.Runtimes.VSCode
  ]

  def modules, do: @modules

  def get(id) do
    id = normalize_id(id)
    Enum.find(@modules, &(apply(&1, :id, []) == id))
  end

  def enrich_integration(%Integration{} = integration) do
    case get(integration.id) do
      nil ->
        integration

      runtime ->
        %Integration{
          integration
          | runtime_transport: runtime.runtime_transport(),
            runtime_auth_owner: runtime.runtime_auth_owner(),
            runtime_session_support: runtime.runtime_session_support(),
            runtime_review_transport: runtime.runtime_review_transport(),
            runtime_capabilities: runtime.capabilities()
        }
    end
  end

  def provider_hint(id, project_root, opts \\ []) do
    case get(id) do
      nil -> nil
      runtime -> runtime.runtime_provider_hint(project_root, opts)
    end
  end

  defp normalize_id(id) do
    id
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("_", "-")
  end
end
