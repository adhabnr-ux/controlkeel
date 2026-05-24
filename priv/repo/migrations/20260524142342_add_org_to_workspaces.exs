defmodule ControlKeel.Repo.Migrations.AddOrgToWorkspaces do
  use Ecto.Migration

  def change do
    alter table(:workspaces) do
      add :org_id, references(:orgs, on_delete: :nilify_all)
    end

    create index(:workspaces, [:org_id])
  end
end
