defmodule ControlKeel.Agent.Runtimes.VSCode do
  @moduledoc false

  @behaviour ControlKeel.Agent.Runtimes.Runtime

  @impl true
  def id, do: "vscode"

  @impl true
  def runtime_transport, do: "vscode_companion"

  @impl true
  def runtime_auth_owner, do: "workspace"

  @impl true
  def runtime_session_support do
    %{"create" => false, "fork" => false, "resume" => false, "streaming" => false}
  end

  @impl true
  def runtime_review_transport, do: "vscode_ipc"

  @impl true
  def runtime_provider_hint(_project_root, _opts), do: nil
  @impl true
  def capabilities do
    %{
      policy_gate: true,
      tool_approval: false,
      user_input_pause_resume: false,
      deterministic_event_ids: false,
      replay_safe_delivery: false
    }
  end
end
