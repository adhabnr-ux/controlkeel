defmodule ControlKeel.Cloud.WorkspaceKey do
  @moduledoc """
  Registered public key for a remote workspace enrolled with this control plane.

  This is the multi-tenant counterpart to the local
  `ControlKeel.Cloud.WorkspaceIdentity`. Each enrolled laptop / project owns
  a row keyed by `workspace_id`, and `AuthToken.verify/1` resolves the
  public key for inbound telemetry tokens through this table.

  See architectural decision D8 in
  [docs/cloud-enterprise-roadmap.md](../../docs/cloud-enterprise-roadmap.md).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Org

  @primary_key {:id, :id, autogenerate: true}
  schema "workspace_keys" do
    field :workspace_id, :string
    field :public_key, :string
    field :fingerprint, :string
    field :algorithm, :string, default: "ed25519"
    field :name, :string
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :org, Org
    belongs_to :mission_workspace, ControlKeel.Mission.Workspace
    timestamps(type: :utc_datetime)
  end

  @required ~w(workspace_id public_key fingerprint algorithm)a
  @optional ~w(name org_id mission_workspace_id last_seen_at revoked_at)a
  @valid_algorithms ~w(ed25519)

  def changeset(key, attrs) do
    key
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:algorithm, @valid_algorithms)
    |> validate_format(:workspace_id, ~r/^ws_[a-z0-9]+$/)
    |> unique_constraint(:workspace_id)
    |> unique_constraint(:fingerprint)
    # Two declarations on purpose: the first matches the index name declared
    # in the migration (used by adapters that surface the DB index name);
    # the second matches the column-derived name that `ecto_sqlite3` builds
    # from the failed UNIQUE constraint, since SQLite errors report columns
    # rather than the index name.
    |> unique_constraint(:mission_workspace_id,
      name: :workspace_keys_org_mission_workspace_unique,
      message: "this project workspace is already enrolled under this org"
    )
    |> unique_constraint(:mission_workspace_id,
      name: :workspace_keys_org_id_mission_workspace_id_index,
      message: "this project workspace is already enrolled under this org"
    )
  end

  @doc "True when the key is currently usable (not revoked)."
  def active?(%__MODULE__{revoked_at: nil}), do: true
  def active?(%__MODULE__{}), do: false
end
