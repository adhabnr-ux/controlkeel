defmodule ControlKeel.Repo.Migrations.AddMissionWorkspaceIdToWorkspaceKeys do
  use Ecto.Migration

  def change do
    alter table(:workspace_keys) do
      add :mission_workspace_id, references(:workspaces, on_delete: :nilify_all)
    end

    create index(:workspace_keys, [:mission_workspace_id])
    create unique_index(:workspace_keys, [:org_id, :mission_workspace_id],
           name: :workspace_keys_org_mission_workspace_unique,
           where: "mission_workspace_id IS NOT NULL AND org_id IS NOT NULL")
  end
end
