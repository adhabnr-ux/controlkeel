defmodule ControlKeel.Repo.Migrations.AddLockVersionForSync do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      add :lock_version, :integer, default: 1, null: false
    end

    alter table(:tasks) do
      add :lock_version, :integer, default: 1, null: false
    end

    alter table(:workspace_agents) do
      add :lock_version, :integer, default: 1, null: false
    end
  end

  def down do
    alter table(:workspace_agents) do
      remove :lock_version
    end

    alter table(:tasks) do
      remove :lock_version
    end

    alter table(:sessions) do
      remove :lock_version
    end
  end
end
