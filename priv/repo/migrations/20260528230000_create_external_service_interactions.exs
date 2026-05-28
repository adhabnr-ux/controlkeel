defmodule ControlKeel.Repo.Migrations.CreateExternalServiceInteractions do
  use Ecto.Migration

  def change do
    create table(:external_service_interactions) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :service_name, :string, null: false
      add :interaction_type, :string, null: false, default: "api_call"
      add :method, :string
      add :endpoint, :string
      add :status_code, :integer
      add :request_size_bytes, :integer, default: 0
      add :response_size_bytes, :integer, default: 0
      add :latency_ms, :integer
      add :tokens_used, :integer, default: 0
      add :cost_cents, :integer, default: 0
      add :redacted, :boolean, default: false
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:external_service_interactions, [:session_id])
    create index(:external_service_interactions, [:service_name])
    create index(:external_service_interactions, [:interaction_type])
  end
end
