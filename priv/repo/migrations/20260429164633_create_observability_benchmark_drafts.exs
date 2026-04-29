defmodule ControlKeel.Repo.Migrations.CreateObservabilityBenchmarkDrafts do
  use Ecto.Migration

  def change do
    create table(:observability_benchmark_drafts) do
      add :title, :string, null: false
      add :suite_slug, :string, null: false
      add :scenario_prompt, :text, null: false
      add :expected_behavior, :text, null: false
      add :evidence_summary, :text
      add :benchmark_hint, :string
      add :status, :string, null: false, default: "draft"
      add :human_gate_required, :boolean, null: false, default: true
      add :metadata, :map, null: false, default: %{}
      add :workspace_id, references(:workspaces, on_delete: :nilify_all)

      add :eval_candidate_id,
          references(:observability_eval_candidates, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:observability_benchmark_drafts, [:eval_candidate_id])
    create index(:observability_benchmark_drafts, [:workspace_id])
    create index(:observability_benchmark_drafts, [:status])
    create index(:observability_benchmark_drafts, [:suite_slug])
  end
end
