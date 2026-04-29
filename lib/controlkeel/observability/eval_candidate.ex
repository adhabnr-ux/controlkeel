defmodule ControlKeel.Observability.EvalCandidate do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Finding, Session, Workspace}

  schema "observability_eval_candidates" do
    field :title, :string
    field :rule_id, :string
    field :category, :string
    field :severity, :string
    field :priority, :string
    field :evidence_kind, :string
    field :evidence_summary, :string
    field :suggested_action, :string
    field :benchmark_hint, :string
    field :source_problem_key, :string
    field :status, :string, default: "open"
    field :human_gate_required, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :session, Session
    belongs_to :finding, Finding

    timestamps(type: :utc_datetime)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :title,
      :rule_id,
      :category,
      :severity,
      :priority,
      :evidence_kind,
      :evidence_summary,
      :suggested_action,
      :benchmark_hint,
      :source_problem_key,
      :status,
      :human_gate_required,
      :metadata,
      :workspace_id,
      :session_id,
      :finding_id
    ])
    |> validate_required([
      :title,
      :rule_id,
      :priority,
      :source_problem_key,
      :status,
      :human_gate_required,
      :metadata
    ])
    |> validate_inclusion(:status, ["open", "approved", "rejected", "archived"])
    |> validate_inclusion(:priority, ["critical", "high", "medium", "low"])
    |> unique_constraint([:workspace_id, :source_problem_key])
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:session)
    |> assoc_constraint(:finding)
  end
end
