defmodule ControlKeel.Mission.SessionDigest do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Mission.Session

  @valid_digest_types ~w(session daily shift_change)
  @external_id_prefix "sd_"

  schema "session_digests" do
    field :external_id, :string
    field :digest_type, :string, default: "session"
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :tasks_completed, :integer, default: 0
    field :tasks_failed, :integer, default: 0
    field :findings_raised, :integer, default: 0
    field :findings_blocked, :integer, default: 0
    field :reviews_pending, :integer, default: 0
    field :reviews_approved, :integer, default: 0
    field :budget_spent_cents, :integer, default: 0
    field :budget_remaining_cents, :integer, default: 0
    field :circuit_breaker_trips, :integer, default: 0
    field :top_rule_ids, :map, default: %{}
    field :top_categories, :map, default: %{}
    field :highlights, :map, default: %{}
    field :needs_attention, :boolean, default: false
    field :generated_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :synced_at, :utc_datetime

    belongs_to :session, Session

    timestamps(type: :utc_datetime)
  end

  def changeset(digest, attrs) do
    digest
    |> cast(attrs, [
      :external_id,
      :session_id,
      :digest_type,
      :period_start,
      :period_end,
      :tasks_completed,
      :tasks_failed,
      :findings_raised,
      :findings_blocked,
      :reviews_pending,
      :reviews_approved,
      :budget_spent_cents,
      :budget_remaining_cents,
      :circuit_breaker_trips,
      :top_rule_ids,
      :top_categories,
      :highlights,
      :needs_attention,
      :generated_at,
      :metadata,
      :synced_at
    ])
    |> validate_required([
      :session_id,
      :digest_type,
      :period_start,
      :period_end,
      :generated_at
    ])
    |> validate_inclusion(:digest_type, @valid_digest_types)
    |> maybe_generate_external_id()
    |> unique_constraint(:external_id)
    |> assoc_constraint(:session)
  end

  defp maybe_generate_external_id(changeset) do
    case get_field(changeset, :external_id) do
      nil ->
        put_change(changeset, :external_id, @external_id_prefix <> TelemetryEnvelope.ulid())

      _ ->
        changeset
    end
  end

  def valid_digest_types, do: @valid_digest_types
end
