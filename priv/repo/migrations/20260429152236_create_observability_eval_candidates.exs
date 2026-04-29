defmodule ControlKeel.Repo.Migrations.CreateObservabilityEvalCandidates do
  use Ecto.Migration

  def change do
    create table(:observability_eval_candidates) do
      add :title, :string, null: false
      add :rule_id, :string, null: false
      add :category, :string
      add :severity, :string
      add :priority, :string, null: false
      add :evidence_kind, :string
      add :evidence_summary, :text
      add :suggested_action, :text
      add :benchmark_hint, :string
      add :source_problem_key, :string, null: false
      add :status, :string, null: false, default: "open"
      add :human_gate_required, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)
      add :session_id, references(:sessions, on_delete: :nilify_all)
      add :finding_id, references(:findings, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:observability_eval_candidates, [:workspace_id, :source_problem_key])
    create index(:observability_eval_candidates, [:workspace_id])
    create index(:observability_eval_candidates, [:status])
    create index(:observability_eval_candidates, [:priority])
  end
end
