defmodule ControlKeel.Repo.Migrations.AddTaskIdToFindings do
  use Ecto.Migration

  def change do
    alter table(:findings) do
      add :task_id, references(:tasks, on_delete: :nilify_all)
    end

    create index(:findings, [:task_id])
    create index(:findings, [:session_id, :task_id])
  end
end
