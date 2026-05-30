defmodule ControlKeel.Repo.Migrations.AddTeamReviewFields do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :assigned_user_id, references(:users, on_delete: :nilify_all)
      add :assigned_by_user_id, references(:users, on_delete: :nilify_all)
      add :assigned_at, :utc_datetime
      add :decided_by_user_id, references(:users, on_delete: :nilify_all)
      add :required_role, :string
    end

    create index(:reviews, [:assigned_user_id, :status])

    create table(:review_audit_events) do
      add :review_id, references(:reviews, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :target_user_id, references(:users, on_delete: :nilify_all)
      add :required_role, :string
      add :actor_role, :string
      add :note, :string
      add :recorded_at, :utc_datetime, null: false
    end

    create index(:review_audit_events, [:review_id, :recorded_at])
    create index(:review_audit_events, [:event_type, :recorded_at])
  end
end
