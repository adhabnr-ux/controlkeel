defmodule ControlKeel.Repo.Migrations.CreateCloudTelemetryEvents do
  use Ecto.Migration

  def change do
    create table(:cloud_telemetry_events) do
      add :event_id, :string, null: false
      add :workspace_id, :string, null: false
      add :kind, :string, null: false
      add :emitted_at, :utc_datetime, null: false
      add :idempotency_key, :string, null: false
      add :redaction_policy_version, :string, null: false
      add :schema_version, :string, null: false, default: "1"
      add :body, :text, null: false
      add :queued_at, :utc_datetime, null: false
      add :sent_at, :utc_datetime
      add :send_attempts, :integer, null: false, default: 0
      add :last_error, :text
    end

    create unique_index(:cloud_telemetry_events, [:event_id])
    create unique_index(:cloud_telemetry_events, [:idempotency_key])
    create index(:cloud_telemetry_events, [:sent_at])
    create index(:cloud_telemetry_events, [:workspace_id, :emitted_at])
  end
end
