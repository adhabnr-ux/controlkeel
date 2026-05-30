defmodule ControlKeel.Repo.Migrations.CreateWorkspaceBaselines do
  use Ecto.Migration

  def change do
    create table(:workspace_baselines) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :window_days, :integer, null: false, default: 7
      add :baseline_data, :text, null: false, default: "{}"
      add :sample_sessions, :integer, null: false, default: 0
      add :computed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_baselines, [:workspace_id])
  end
end
