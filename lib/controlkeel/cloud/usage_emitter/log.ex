defmodule ControlKeel.Cloud.UsageEmitter.Log do
  @moduledoc """
  Default usage emitter that logs spend events.

  Enable via:
      config :controlkeel, :usage_emitter, ControlKeel.Cloud.UsageEmitter.Log
  """

  @behaviour ControlKeel.Cloud.UsageEmitter

  require Logger

  @impl true
  def emit_usage(org_id, %{spend_cents: cents, date: date}) do
    Logger.info("[usage] org=#{org_id} date=#{date} spend_cents=#{cents}")
    :ok
  end
end
