defmodule ControlKeel.Repo.Migrations.CreateSessionDigests do
  use Ecto.Migration

  def change do
    create table(:session_digests) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :digest_type, :string, null: false, default: "session"
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :tasks_completed, :integer, default: 0
      add :tasks_failed, :integer, default: 0
      add :findings_raised, :integer, default: 0
      add :findings_blocked, :integer, default: 0
      add :reviews_pending, :integer, default: 0
      add :reviews_approved, :integer, default: 0
      add :budget_spent_cents, :integer, default: 0
      add :budget_remaining_cents, :integer, default: 0
      add :circuit_breaker_trips, :integer, default: 0
      add :top_rule_ids, :map, default: %{}
      add :top_categories, :map, default: %{}
      add :highlights, :map, default: %{}
      add :needs_attention, :boolean, default: false
      add :generated_at, :utc_datetime, null: false
      add :metadata, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create index(:session_digests, [:session_id])
    create index(:session_digests, [:needs_attention])
  end
end
