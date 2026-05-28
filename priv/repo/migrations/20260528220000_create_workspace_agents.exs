defmodule ControlKeel.Repo.Migrations.CreateWorkspaceAgents do
  use Ecto.Migration

  def change do
    create table(:workspace_agents) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :external_id, :string
      add :name, :string, null: false
      add :role, :string, null: false, default: "specialized"
      add :agent_type, :string, null: false
      add :status, :string, null: false, default: "active"
      add :scope, :map, default: %{}
      add :budget_cents, :integer, default: 0
      add :spent_cents, :integer, default: 0
      add :policy_overrides, :map, default: %{}
      add :maintainer_id, :integer
      add :sessions_count, :integer, default: 0
      add :last_active_at, :utc_datetime
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:workspace_agents, [:workspace_id])
    create unique_index(:workspace_agents, [:external_id])
    create unique_index(:workspace_agents, [:workspace_id, :role])
  end
end
