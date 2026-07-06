defmodule ControlKeel.Cloud.Usage.Emitter.Log do
  @moduledoc """
  Default usage emitter that logs spend events.

  Enable via:
      config :controlkeel, :usage_emitter, ControlKeel.Cloud.Usage.Emitter.Log
  """

  @behaviour ControlKeel.Cloud.Usage.Emitter

  require Logger

  @impl true
  def emit_usage(org_id, %{spend_cents: cents, date: date}) do
    Logger.info("[usage] org=#{org_id} date=#{date} spend_cents=#{cents}")
    :ok
  end
end
