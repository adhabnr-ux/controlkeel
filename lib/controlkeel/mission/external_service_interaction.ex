defmodule ControlKeel.Mission.ExternalServiceInteraction do
  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.{Session, Task}

  @valid_interaction_types ~w(api_call webhook browser_action)

  schema "external_service_interactions" do
    field :service_name, :string
    field :interaction_type, :string, default: "api_call"
    field :method, :string
    field :endpoint, :string
    field :status_code, :integer
    field :request_size_bytes, :integer, default: 0
    field :response_size_bytes, :integer, default: 0
    field :latency_ms, :integer
    field :tokens_used, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :redacted, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :session, Session
    belongs_to :task, Task

    timestamps(type: :utc_datetime)
  end

  def changeset(interaction, attrs) do
    interaction
    |> cast(attrs, [
      :session_id,
      :task_id,
      :service_name,
      :interaction_type,
      :method,
      :endpoint,
      :status_code,
      :request_size_bytes,
      :response_size_bytes,
      :latency_ms,
      :tokens_used,
      :cost_cents,
      :redacted,
      :metadata
    ])
    |> validate_required([:session_id, :service_name])
    |> validate_inclusion(:interaction_type, @valid_interaction_types)
    |> assoc_constraint(:session)
    |> maybe_redact_endpoint()
  end

  defp maybe_redact_endpoint(changeset) do
    case get_field(changeset, :endpoint) do
      nil ->
        changeset

      endpoint ->
        redacted = redact_patterns(endpoint)

        if redacted != endpoint do
          changeset
          |> put_change(:endpoint, redacted)
          |> put_change(:redacted, true)
        else
          changeset
        end
    end
  end

  defp redact_patterns(endpoint) do
    endpoint
    |> redact_tokens()
    |> redact_emails()
  end

  defp redact_tokens(str) do
    String.replace(str, ~r/(token|key|secret|password|api_key)=([^&\s]+)/, "\\1=[REDACTED]")
  end

  defp redact_emails(str) do
    String.replace(str, ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, "[EMAIL_REDACTED]")
  end
end
