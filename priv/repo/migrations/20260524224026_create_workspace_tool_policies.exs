defmodule ControlKeel.Repo.Migrations.CreateWorkspaceToolPolicies do
  use Ecto.Migration

  def change do
    create table(:workspace_tool_policies) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :mode, :string, null: false, default: "inherit"
      add :tools, :text, null: false, default: "[]"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:workspace_tool_policies, [:workspace_id])
  end
end
