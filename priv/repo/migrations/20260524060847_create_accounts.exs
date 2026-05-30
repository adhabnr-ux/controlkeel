defmodule ControlKeel.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :status, :string, null: false, default: "active"
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:status])

    create table(:orgs) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "active"
      add :settings, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:orgs, [:slug])

    create table(:memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :org_id, references(:orgs, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "active"
      add :invited_by_user_id, references(:users, on_delete: :nilify_all)
      add :invitation_token_hash, :string
      add :invited_at, :utc_datetime
      add :accepted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :org_id])
    create unique_index(:memberships, [:invitation_token_hash])
    create index(:memberships, [:org_id, :status])
    create index(:memberships, [:user_id, :status])
  end
end
