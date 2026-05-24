defmodule ControlKeel.Accounts.Membership do
  @moduledoc """
  Join between a user and an org, with role and invitation lifecycle.

  Roles ladder (highest to lowest):

    - `owner`   — full org control; can transfer ownership
    - `admin`   — manage members, policies, budgets, but cannot delete org
    - `member`  — read/write within their workspaces
    - `viewer`  — read-only access

  Invitation flow: `Accounts.invite_member/3` creates a `pending` membership
  with `invitation_token_hash` set. The invitee accepts via the raw token,
  which clears the hash and sets `accepted_at`. After acceptance the
  membership becomes `active`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Accounts.Org
  alias ControlKeel.Accounts.User

  @primary_key {:id, :id, autogenerate: true}
  schema "memberships" do
    field :role, :string, default: "member"
    field :status, :string, default: "pending"
    field :invitation_token_hash, :string
    field :invited_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :invited_by_user_id, :integer

    belongs_to :user, User
    belongs_to :org, Org
    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(owner admin member viewer)
  @valid_statuses ~w(pending active revoked)

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :user_id,
      :org_id,
      :role,
      :status,
      :invitation_token_hash,
      :invited_at,
      :accepted_at,
      :invited_by_user_id
    ])
    |> validate_required([:user_id, :org_id, :role, :status])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_inclusion(:status, @valid_statuses)
    |> assoc_constraint(:user)
    |> assoc_constraint(:org)
    |> unique_constraint([:user_id, :org_id], name: :memberships_user_id_org_id_index)
    |> unique_constraint(:invitation_token_hash)
  end

  @doc "True when the membership grants active access."
  def active?(%__MODULE__{status: "active"}), do: true
  def active?(%__MODULE__{}), do: false
end
