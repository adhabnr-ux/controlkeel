defmodule ControlKeel.Repo.Migrations.CreateCloudReceivedTelemetryEvents do
  use Ecto.Migration

  def change do
    create table(:cloud_received_telemetry_events) do
      add :event_id, :string, null: false
      add :workspace_id, :string, null: false
      add :kind, :string, null: false
      add :emitted_at, :utc_datetime, null: false
      add :received_at, :utc_datetime, null: false
      add :idempotency_key, :string, null: false
      add :redaction_policy_version, :string, null: false
      add :schema_version, :string, null: false, default: "1"
      add :body, :text, null: false
      add :source_workspace_id, :string
    end

    create unique_index(:cloud_received_telemetry_events, [:event_id])
    create unique_index(:cloud_received_telemetry_events, [:idempotency_key])
    create index(:cloud_received_telemetry_events, [:workspace_id, :emitted_at])
    create index(:cloud_received_telemetry_events, [:kind, :received_at])
  end
end
