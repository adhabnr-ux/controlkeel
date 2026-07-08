defmodule ControlKeel.Platform.NhiAuditEvent do
  @moduledoc """
  Lifecycle audit event for a Non-Human Identity (service account).

  Events:
    - `"provisioned"` — identity created and issued a token
    - `"token_rotated"` — token was rotated; prior token is invalid
    - `"deprovisioned"` — identity revoked; no further calls allowed
    - `"last_used_updated"` — last_used_at refreshed on authentication
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Platform.ServiceAccount

  @event_types ~w(provisioned token_rotated deprovisioned last_used_updated)

  schema "nhi_audit_events" do
    field :event_type, :string
    field :actor, :string
    field :metadata, :string, default: "{}"
    field :occurred_at, :utc_datetime

    belongs_to :service_account, ServiceAccount

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:service_account_id, :event_type, :actor, :metadata, :occurred_at])
    |> validate_required([:service_account_id, :event_type, :occurred_at])
    |> validate_inclusion(:event_type, @event_types)
    |> assoc_constraint(:service_account)
  end

  @doc "Decode stored JSON metadata."
  def decode_metadata(%__MODULE__{metadata: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  def decode_metadata(_), do: %{}
end
