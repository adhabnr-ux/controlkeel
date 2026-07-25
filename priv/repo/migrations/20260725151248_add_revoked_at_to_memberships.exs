defmodule ControlKeel.Repo.Migrations.AddRevokedAtToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      add :revoked_at, :utc_datetime
    end
  end
end
