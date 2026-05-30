defmodule ControlKeel.Cloud.TelemetryEvent do
  @moduledoc """
  Ecto schema for a queued cloud telemetry event awaiting sync.

  Rows are inserted by `ControlKeel.Cloud.TelemetryQueue.enqueue/1`. The sender
  (a later slice) reads pending rows, posts them upstream, then marks them as
  sent. `event_id` and `idempotency_key` are both unique so the queue never
  duplicates work even under crash-recovery enqueue replays.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "cloud_telemetry_events" do
    field :event_id, :string
    field :workspace_id, :string
    field :kind, :string
    field :emitted_at, :utc_datetime
    field :idempotency_key, :string
    field :redaction_policy_version, :string
    field :schema_version, :string, default: "1"
    field :body, :string
    field :queued_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :send_attempts, :integer, default: 0
    field :last_error, :string
  end

  @required ~w(event_id workspace_id kind emitted_at idempotency_key
              redaction_policy_version schema_version body queued_at)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required ++ [:sent_at, :send_attempts, :last_error])
    |> validate_required(@required)
    |> unique_constraint(:event_id)
    |> unique_constraint(:idempotency_key)
  end
end
