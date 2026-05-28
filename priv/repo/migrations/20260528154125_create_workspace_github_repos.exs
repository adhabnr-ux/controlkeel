defmodule ControlKeel.Repo.Migrations.CreateWorkspaceGithubRepos do
  use Ecto.Migration

  def change do
    create table(:workspace_github_repos) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all), null: false
      add :owner, :string, null: false
      add :repo, :string, null: false
      add :default_branch, :string
      add :installation_id, :string
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspace_github_repos, [:workspace_id])
    create unique_index(:workspace_github_repos, [:workspace_id, :owner, :repo])
  end
end
