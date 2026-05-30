defmodule ControlKeel.Repo.Migrations.PartialUniqueWorkspaceAgentsPrimary do
  use Ecto.Migration

  def up do
    drop_if_exists index(:workspace_agents, [:workspace_id, :role])

    create unique_index(:workspace_agents, [:workspace_id],
             where: "role = 'primary' AND status != 'retired'",
             name: :workspace_agents_primary_unique
           )
  end

  def down do
    drop_if_exists index(:workspace_agents, [:workspace_id],
                     name: :workspace_agents_primary_unique
                   )

    create unique_index(:workspace_agents, [:workspace_id, :role])
  end
end
