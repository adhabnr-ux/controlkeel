defmodule ControlKeel.Cloud.Usage.Emitter do
  @moduledoc """
  Behaviour for usage emission adapters.

  The default is no emitter (nil). Configure via:
      config :controlkeel, :usage_emitter, ControlKeel.Cloud.Usage.Emitter.Log

  Future adapters:
  - `ControlKeel.Cloud.Usage.Emitter.Stripe` — Stripe Metering Events API
  - `ControlKeel.Cloud.Usage.Emitter.Webhook` — POST to a billing webhook
  """

  @callback emit_usage(org_id :: integer(), usage :: map()) :: :ok | {:error, term()}
end
