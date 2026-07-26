defmodule ControlKeel.Repo.Migrations.DropOrgIdentityProviderSetting do
  use Ecto.Migration

  def up do
    case repo().__adapter__() do
      Ecto.Adapters.SQLite3 ->
        execute """
        UPDATE orgs
        SET settings = json_remove(settings, '$.identity_provider')
        WHERE settings IS NOT NULL
          AND json_valid(settings)
          AND json_type(settings, '$.identity_provider') IS NOT NULL
        """

      Ecto.Adapters.Postgres ->
        execute """
        UPDATE orgs
        SET settings = settings - 'identity_provider'
        WHERE settings ? 'identity_provider'
        """
    end
  end

  def down do
    :ok
  end
end
