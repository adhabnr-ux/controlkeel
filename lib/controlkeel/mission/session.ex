defmodule ControlKeel.Mission.Session do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Memory.Record

  alias ControlKeel.Mission.{
    Finding,
    Invocation,
    ProofBundle,
    Review,
    SessionEvent,
    Task,
    TaskCheckpoint,
    Workspace
  }

  alias ControlKeel.Platform.{AuditExport, TaskEdge, TaskRun}

  @external_id_prefix "ses_"

  schema "sessions" do
    field :external_id, :string
    field :title, :string
    field :objective, :string
    field :risk_tier, :string
    field :status, :string, default: "planned"
    field :budget_cents, :integer, default: 0
    field :daily_budget_cents, :integer, default: 0
    field :spent_cents, :integer, default: 0
    field :proxy_token, :string
    field :execution_brief, :map, default: %{}
    field :metadata, :map, default: %{}
    field :synced_at, :utc_datetime
    field :lock_version, :integer, default: 1

    belongs_to :workspace, Workspace
    has_many :tasks, Task
    has_many :findings, Finding
    has_many :invocations, Invocation
    has_many :proof_bundles, ProofBundle
    has_many :reviews, Review
    has_many :session_events, SessionEvent
    has_many :task_checkpoints, TaskCheckpoint
    has_many :memory_records, Record
    has_many :task_edges, TaskEdge
    has_many :task_runs, TaskRun
    has_many :audit_exports, AuditExport

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :external_id,
      :title,
      :objective,
      :risk_tier,
      :status,
      :budget_cents,
      :daily_budget_cents,
      :spent_cents,
      :proxy_token,
      :execution_brief,
      :metadata,
      :synced_at,
      :lock_version,
      :workspace_id
    ])
    |> ensure_proxy_token()
    |> validate_required([
      :title,
      :objective,
      :risk_tier,
      :status,
      :budget_cents,
      :daily_budget_cents,
      :spent_cents,
      :proxy_token,
      :execution_brief,
      :workspace_id
    ])
    |> validate_number(:budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:daily_budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:spent_cents, greater_than_or_equal_to: 0)
    |> validate_format(:external_id, ~r/^ses_[0-9A-Z]{26}$|^ses_legacy_[0-9]+$/,
      message: "must be ses_<ulid> or ses_legacy_<id>"
    )
    |> maybe_generate_external_id()
    |> unique_constraint(:external_id)
    |> unique_constraint(:proxy_token)
    |> assoc_constraint(:workspace)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. Anything not listed here
  is dropped from the serialized payload.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :workspace_id,
       :title,
       :objective,
       :risk_tier,
       :status,
       :budget_cents,
       :daily_budget_cents,
       :spent_cents,
       :execution_brief,
       :metadata,
       :synced_at,
       :lock_version,
       :inserted_at,
       :updated_at
     ]}
  end

  defp maybe_generate_external_id(changeset) do
    case get_field(changeset, :external_id) do
      nil ->
        put_change(changeset, :external_id, @external_id_prefix <> TelemetryEnvelope.ulid())

      _ ->
        changeset
    end
  end

  defp ensure_proxy_token(changeset) do
    case get_field(changeset, :proxy_token) do
      value when is_binary(value) and value != "" ->
        changeset

      _ ->
        put_change(changeset, :proxy_token, generate_proxy_token())
    end
  end

  defp generate_proxy_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
