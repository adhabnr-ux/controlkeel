defmodule ControlKeel.Cloud.RuntimeDispatcher.RemoteRequired do
  @moduledoc """
  Remote-mode fallback: refuse manual/local handoff when the selected runtime
  mode says governed workload surfaces must execute in cloud/self-host.

  Operators must configure `:cloud_dispatchers` for the runtime target before
  dispatch can proceed. This keeps cloud/self-host modes fail-closed instead
  of silently becoming a local/manual workflow.
  """

  @behaviour ControlKeel.Cloud.RuntimeDispatcher

  @impl true
  def dispatch(package, _opts) do
    {:error,
     {:remote_dispatcher_required,
      %{
        runtime_target: package.runtime_target,
        runtime_mode: ControlKeel.Runtime.mode(),
        message:
          "Configure :cloud_dispatchers for #{package.runtime_target} before dispatching in remote mode."
      }}}
  end
end
