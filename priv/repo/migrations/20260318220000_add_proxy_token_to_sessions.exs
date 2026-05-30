defmodule ControlKeel.Repo.Migrations.AddProxyTokenToSessions do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      add :proxy_token, :string
    end

    if sqlite_repo?() do
      execute("""
      UPDATE sessions
      SET proxy_token = lower(hex(randomblob(24)))
      WHERE proxy_token IS NULL
      """)
    else
      execute("""
      UPDATE sessions
      SET proxy_token = encode(gen_random_bytes(24), 'hex')
      WHERE proxy_token IS NULL
      """)
    end

    create unique_index(:sessions, [:proxy_token])
  end

  def down do
    drop_if_exists unique_index(:sessions, [:proxy_token])

    alter table(:sessions) do
      remove :proxy_token
    end
  end

  defp sqlite_repo?, do: repo().__adapter__() == Ecto.Adapters.SQLite3
end
