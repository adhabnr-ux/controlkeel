defmodule ControlKeel.Repo.Migrations.CreateObservabilityImports do
  use Ecto.Migration

  def change do
    create table(:observability_imports) do
      add :schema_version, :string, null: false
      add :exported_at, :utc_datetime
      add :source, :map, null: false, default: %{}
      add :original_session_id, :integer
      add :original_session_title, :string
      add :health, :string
      add :problem_groups, :integer, null: false, default: 0
      add :total_problem_findings, :integer, null: false, default: 0
      add :redaction_policy, :string
      add :integrity_status, :string, null: false
      add :payload_sha256, :string, null: false
      add :import_mode, :string, null: false, default: "local_persist"
      add :imported_at, :utc_datetime, null: false
      add :envelope, :map, null: false, default: %{}
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :session_id, references(:sessions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:observability_imports, [:payload_sha256])
    create index(:observability_imports, [:workspace_id])
    create index(:observability_imports, [:session_id])
    create index(:observability_imports, [:original_session_id])
  end
end
