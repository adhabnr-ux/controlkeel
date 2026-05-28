defmodule ControlKeel.Repo.Migrations.AddMissionWorkspaceIdToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :mission_workspace_id, references(:workspaces, on_delete: :nilify_all)
    end

    create index(:memberships, [:mission_workspace_id])
  end
end
