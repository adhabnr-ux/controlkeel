defmodule ControlKeel.Cloud.RuntimeDispatcher.Manual do
  @moduledoc """
  Default dispatcher: records that the operator will hand-deliver the
  callback token to the target runtime out of band.

  This is the honest default for runtimes that have no programmatic
  dispatch API (Devin's web UI, ad-hoc Cursor cloud-agent runs) or for
  deployments that haven't yet configured a runtime-specific dispatcher.
  """

  @behaviour ControlKeel.Cloud.RuntimeDispatcher

  @impl true
  def dispatch(package, _opts) do
    {:ok,
     %{
       "mode" => "manual",
       "runtime_target" => package.runtime_target,
       "note" =>
         "Operator hands callback token to #{package.runtime_target} out of band; runtime calls back to /cloud/v1/runtime/callbacks."
     }}
  end
end
