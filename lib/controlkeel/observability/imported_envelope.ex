defmodule ControlKeel.Observability.ImportedEnvelope do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Workspace}

  schema "observability_imports" do
    field :schema_version, :string
    field :exported_at, :utc_datetime
    field :source, :map, default: %{}
    field :original_session_id, :integer
    field :original_session_title, :string
    field :health, :string
    field :problem_groups, :integer, default: 0
    field :total_problem_findings, :integer, default: 0
    field :redaction_policy, :string
    field :integrity_status, :string
    field :payload_sha256, :string
    field :import_mode, :string, default: "local_persist"
    field :imported_at, :utc_datetime
    field :envelope, :map, default: %{}

    belongs_to :workspace, Workspace
    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  def changeset(imported_envelope, attrs) do
    imported_envelope
    |> cast(attrs, [
      :schema_version,
      :exported_at,
      :source,
      :original_session_id,
      :original_session_title,
      :health,
      :problem_groups,
      :total_problem_findings,
      :redaction_policy,
      :integrity_status,
      :payload_sha256,
      :import_mode,
      :imported_at,
      :envelope,
      :workspace_id,
      :session_id
    ])
    |> validate_required([
      :schema_version,
      :source,
      :problem_groups,
      :total_problem_findings,
      :integrity_status,
      :payload_sha256,
      :import_mode,
      :imported_at,
      :envelope
    ])
    |> validate_number(:problem_groups, greater_than_or_equal_to: 0)
    |> validate_number(:total_problem_findings, greater_than_or_equal_to: 0)
    |> validate_length(:payload_sha256, is: 64)
    |> unique_constraint(:payload_sha256)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:session)
  end
end
