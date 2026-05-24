defmodule ControlKeel.Repo.Migrations.CreateCloudRunPackages do
  use Ecto.Migration

  def change do
    create table(:cloud_run_packages) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :runtime_target, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :callback_token_hash, :string, null: false
      add :scopes, :text
      add :budget_cents_allocated, :integer, null: false, default: 0
      add :proof_refs, :text
      add :payload, :map, null: false, default: %{}
      add :result_summary, :string
      add :error_summary, :string
      add :dispatched_at, :utc_datetime
      add :completed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:cloud_run_packages, [:callback_token_hash])
    create index(:cloud_run_packages, [:workspace_id, :status])
    create index(:cloud_run_packages, [:runtime_target, :status])
    create index(:cloud_run_packages, [:task_id])
  end
end
