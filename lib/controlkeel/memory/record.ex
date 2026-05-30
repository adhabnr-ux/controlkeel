defmodule ControlKeel.Memory.Record do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Memory.Embedding
  alias ControlKeel.Mission.{Session, Task, Workspace}
  alias ControlKeel.Types.JsonList

  schema "memory_records" do
    field :external_id, :string
    field :record_type, :string
    field :title, :string
    field :summary, :string
    field :body, :string, default: ""
    field :tags, JsonList, default: []
    field :source_type, :string
    field :source_id, :string
    field :metadata, :map, default: %{}
    field :archived_at, :utc_datetime
    field :visibility, :string, default: "workspace"
    field :shared_org_id, :integer
    field :synced_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :session, Session
    belongs_to :task, Task
    has_many :embeddings, Embedding, foreign_key: :memory_record_id

    timestamps(type: :utc_datetime)
  end

  @external_id_prefix "mem_"

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :external_id,
      :workspace_id,
      :session_id,
      :task_id,
      :record_type,
      :title,
      :summary,
      :body,
      :tags,
      :source_type,
      :source_id,
      :metadata,
      :archived_at,
      :visibility,
      :shared_org_id,
      :synced_at
    ])
    |> validate_required([
      :workspace_id,
      :session_id,
      :record_type,
      :title,
      :summary,
      :body,
      :tags,
      :source_type,
      :metadata
    ])
    |> maybe_generate_external_id()
    |> unique_constraint(:external_id)
    |> assoc_constraint(:workspace)
    |> assoc_constraint(:session)
    |> assoc_constraint(:task)
  end

  @doc """
  Allowlist of fields safe to ship via cloud sync. `title`, `summary`, `body`,
  and `metadata` are passed through `Cloud.Redactor.redact_value/1` because
  users sometimes paste credentials into free-form memory content.
  """
  def sync_fields do
    {:include,
     [
       :id,
       :external_id,
       :workspace_id,
       :session_id,
       :task_id,
       :record_type,
       {:redact, :title},
       {:redact, :summary},
       {:redact, :body},
       :tags,
       :source_type,
       :source_id,
       {:redact, :metadata},
       :archived_at,
       :visibility,
       :shared_org_id,
       :synced_at,
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
end
