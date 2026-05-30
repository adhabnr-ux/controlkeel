defmodule ControlKeel.Cloud.UsageEmitter do
  @moduledoc """
  Behaviour for usage emission adapters.

  The default is no emitter (nil). Configure via:
      config :controlkeel, :usage_emitter, ControlKeel.Cloud.UsageEmitter.Log

  Future adapters:
  - `ControlKeel.Cloud.UsageEmitter.Stripe` — Stripe Metering Events API
  - `ControlKeel.Cloud.UsageEmitter.Webhook` — POST to a billing webhook
  """

  @callback emit_usage(org_id :: integer(), usage :: map()) :: :ok | {:error, term()}
end
