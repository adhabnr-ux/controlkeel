defmodule ControlKeel.Repo.Migrations.CreateRollbackSnapshots do
  use Ecto.Migration

  def change do
    create table(:rollback_snapshots) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :commit_sha_before, :string, null: false
      add :commit_sha_after, :string
      add :status, :string, null: false, default: "available"
      add :rollback_method, :string, null: false, default: "git_revert"
      add :safety_check, :map, default: %{}
      add :rolled_back_at, :utc_datetime
      add :rolled_back_by, :string
      add :finding_id, references(:findings, on_delete: :nilify_all)
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:rollback_snapshots, [:session_id])
    create index(:rollback_snapshots, [:task_id])
    create index(:rollback_snapshots, [:status])
  end
end
