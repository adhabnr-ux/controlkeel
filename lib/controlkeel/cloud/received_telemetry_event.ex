defmodule ControlKeel.Cloud.ReceivedTelemetryEvent do
  @moduledoc """
  Persisted record of a telemetry envelope received from an upstream-pushing
  workspace. Distinct from `ControlKeel.Cloud.TelemetryEvent`, which is the
  outbound queue for this workspace's own events.

  In self-host mode the same Phoenix app is often both sender and receiver.
  Keeping the outbound queue and the inbound log as separate tables makes the
  data flow inspectable and prevents accidental mixing of pending-send vs.
  durable-audit rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "cloud_received_telemetry_events" do
    field :event_id, :string
    field :workspace_id, :string
    field :kind, :string
    field :emitted_at, :utc_datetime
    field :received_at, :utc_datetime
    field :idempotency_key, :string
    field :redaction_policy_version, :string
    field :schema_version, :string, default: "1"
    field :body, :string
    field :source_workspace_id, :string
  end

  @required ~w(event_id workspace_id kind emitted_at received_at idempotency_key
              redaction_policy_version schema_version body)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required ++ [:source_workspace_id])
    |> validate_required(@required)
    |> unique_constraint(:event_id)
    |> unique_constraint(:idempotency_key)
  end
end
