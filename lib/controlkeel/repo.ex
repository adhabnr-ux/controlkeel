defmodule ControlKeel.Repo do
  @adapter (case System.get_env("CK_DB_ADAPTER", "sqlite3") do
              "postgres" -> Ecto.Adapters.Postgres
              _ -> Ecto.Adapters.SQLite3
            end)

  use Ecto.Repo,
    otp_app: :controlkeel,
    adapter: @adapter
end
