defmodule ControlKeel.Repo.Migrations.AddExternalIdToSessions do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    # Backfill existing rows with a legacy prefix so they remain addressable
    # by external_id without colliding with newly-issued ULIDs (pattern
    # matches Task.external_id legacy backfill).
    execute("""
    UPDATE sessions
       SET external_id = 'ses_legacy_' || id
     WHERE external_id IS NULL
    """)

    create unique_index(:sessions, [:external_id], where: "external_id IS NOT NULL")
    create index(:sessions, [:synced_at])
  end

  def down do
    drop index(:sessions, [:synced_at])
    drop unique_index(:sessions, [:external_id])

    alter table(:sessions) do
      remove :synced_at
      remove :external_id
    end
  end
end
