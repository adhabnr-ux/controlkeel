defmodule ControlKeel.Repo.Migrations.AddGitMetadataToCloudRunPackages do
  use Ecto.Migration

  def change do
    alter table(:cloud_run_packages) do
      add :repo_url, :string
      add :branch, :string
      add :commit_sha, :string
    end

    create index(:cloud_run_packages, [:commit_sha])
  end
end
