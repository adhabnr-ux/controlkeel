defmodule ControlKeel.Mission.WorkspaceGithubRepo do
  @moduledoc """
  A bind between a mission workspace and a GitHub repository.

  This is the data half of `CK-CLOUD-GIT-001`. ControlKeel itself does not
  yet act as a GitHub App — there is no webhook handler, no installation
  token exchange, no PR governance round-trip. What this schema gives an
  operator is a *declared* binding: "this project workspace operates on
  `owner/repo`", which the cloud handoff path can include in run packages
  so downstream runtimes know which code to fetch.

  `installation_id` is stored as a string and left nullable so a future
  slice that wires a real GitHub App can populate it without a schema
  migration. `metadata` is a free-form map for the same reason
  (default-branch override, app slug, webhook secret reference, etc.).

  Uniqueness is `(workspace_id, owner, repo)` so a workspace can have
  multiple bound repos (a polyrepo monorepo replacement) but cannot
  bind the same repo twice.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ControlKeel.Mission.Workspace

  schema "workspace_github_repos" do
    field :owner, :string
    field :repo, :string
    field :default_branch, :string
    field :installation_id, :string
    field :metadata, :map, default: %{}

    belongs_to :workspace, Workspace

    timestamps(type: :utc_datetime)
  end

  @required ~w(workspace_id owner repo)a
  @optional ~w(default_branch installation_id metadata)a

  def changeset(repo, attrs) do
    repo
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_format(:owner, ~r/^[A-Za-z0-9][A-Za-z0-9._-]*$/,
      message: "must look like a GitHub owner"
    )
    |> validate_format(:repo, ~r/^[A-Za-z0-9._-]+$/, message: "must look like a GitHub repo name")
    |> assoc_constraint(:workspace)
    |> unique_constraint([:workspace_id, :owner, :repo],
      name: :workspace_github_repos_workspace_id_owner_repo_index,
      message: "this repository is already bound to the workspace"
    )
  end

  @doc "Returns the canonical `https://github.com/owner/repo` URL."
  @spec html_url(%__MODULE__{}) :: String.t()
  def html_url(%__MODULE__{owner: owner, repo: repo}),
    do: "https://github.com/#{owner}/#{repo}"
end
