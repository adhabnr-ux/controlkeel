defmodule ControlKeel.Observability.BenchmarkDraft do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Observability.EvalCandidate

  schema "observability_benchmark_drafts" do
    field :title, :string
    field :suite_slug, :string
    field :scenario_prompt, :string
    field :expected_behavior, :string
    field :evidence_summary, :string
    field :benchmark_hint, :string
    field :status, :string, default: "draft"
    field :human_gate_required, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :eval_candidate, EvalCandidate

    timestamps(type: :utc_datetime)
  end

  def changeset(draft, attrs) do
    draft
    |> cast(attrs, [
      :title,
      :suite_slug,
      :scenario_prompt,
      :expected_behavior,
      :evidence_summary,
      :benchmark_hint,
      :status,
      :human_gate_required,
      :metadata,
      :workspace_id,
      :eval_candidate_id
    ])
    |> validate_required([
      :title,
      :suite_slug,
      :scenario_prompt,
      :expected_behavior,
      :status,
      :human_gate_required,
      :metadata,
      :eval_candidate_id
    ])
    |> validate_inclusion(:status, ["draft", "approved", "rejected", "archived"])
    |> validate_length(:suite_slug, min: 3)
    |> unique_constraint(:eval_candidate_id)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:eval_candidate)
  end
end
