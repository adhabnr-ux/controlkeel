defmodule ControlKeel.Repo.Migrations.CreateNhiAuditEvents do
  use Ecto.Migration

  def change do
    create table(:nhi_audit_events) do
      add :service_account_id, references(:service_accounts, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :actor, :string
      add :metadata, :text, null: false, default: "{}"
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:nhi_audit_events, [:service_account_id])
    create index(:nhi_audit_events, [:event_type])
    create index(:nhi_audit_events, [:occurred_at])
  end
end
