defmodule ControlKeel.Repo.Local do
  @moduledoc """
  SQLite-backed Ecto repo used in local runtime mode.

  The adapter is selected at compile time via the `CK_DB_ADAPTER` env var so the
  test suite can run against Postgres in the `test-postgres` CI lane. Production
  cloud mode does **not** go through this module — it routes through
  `ControlKeel.Repo` to `ControlKeel.CloudRepo`. See `lib/controlkeel/repo.ex`.
  """

  @adapter (case System.get_env("CK_DB_ADAPTER", "sqlite3") do
              "postgres" -> Ecto.Adapters.Postgres
              _ -> Ecto.Adapters.SQLite3
            end)

  use Ecto.Repo,
    otp_app: :controlkeel,
    adapter: @adapter
end
