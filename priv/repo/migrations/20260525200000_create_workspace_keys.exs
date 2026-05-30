defmodule ControlKeel.Repo.Migrations.CreateWorkspaceKeys do
  use Ecto.Migration

  def change do
    create table(:workspace_keys) do
      add :workspace_id, :string, null: false
      add :public_key, :text, null: false
      add :fingerprint, :string, null: false
      add :algorithm, :string, null: false, default: "ed25519"
      add :name, :string
      add :org_id, :integer
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_keys, [:workspace_id])
    create unique_index(:workspace_keys, [:fingerprint])
    create index(:workspace_keys, [:org_id])
    create index(:workspace_keys, [:revoked_at])
  end
end
