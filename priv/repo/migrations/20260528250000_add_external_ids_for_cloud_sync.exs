defmodule ControlKeel.Repo.Migrations.AddExternalIdsForCloudSync do
  use Ecto.Migration

  def up do
    alter table(:findings) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    alter table(:memory_records) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    alter table(:session_digests) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    alter table(:reviews) do
      add :external_id, :string
      add :synced_at, :utc_datetime
    end

    create unique_index(:findings, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:memory_records, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:session_digests, [:external_id], where: "external_id IS NOT NULL")
    create unique_index(:reviews, [:external_id], where: "external_id IS NOT NULL")

    create index(:findings, [:synced_at])
    create index(:memory_records, [:synced_at])
    create index(:session_digests, [:synced_at])
    create index(:reviews, [:synced_at])
  end

  def down do
    drop index(:reviews, [:synced_at])
    drop index(:session_digests, [:synced_at])
    drop index(:memory_records, [:synced_at])
    drop index(:findings, [:synced_at])

    drop unique_index(:reviews, [:external_id])
    drop unique_index(:session_digests, [:external_id])
    drop unique_index(:memory_records, [:external_id])
    drop unique_index(:findings, [:external_id])

    alter table(:reviews) do
      remove :synced_at
      remove :external_id
    end

    alter table(:session_digests) do
      remove :synced_at
      remove :external_id
    end

    alter table(:memory_records) do
      remove :synced_at
      remove :external_id
    end

    alter table(:findings) do
      remove :synced_at
      remove :external_id
    end
  end
end
