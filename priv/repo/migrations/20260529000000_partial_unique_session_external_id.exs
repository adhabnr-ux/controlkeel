defmodule ControlKeel.Repo.Migrations.PartialUniqueSessionExternalId do
  use Ecto.Migration

  def up do
    # Prevent duplicate session inserts for the same external_id within a
    # workspace. SQLite + Postgres both support partial unique indexes; the
    # WHERE clause excludes pre-external_id legacy rows that have NULL.
    create unique_index(:sessions, [:workspace_id, :external_id],
             where: "external_id IS NOT NULL",
             name: :sessions_workspace_id_external_id_partial_index
           )
  end

  def down do
    drop_if_exists index(:sessions, [:workspace_id, :external_id],
                     name: :sessions_workspace_id_external_id_partial_index
                   )
  end
end
