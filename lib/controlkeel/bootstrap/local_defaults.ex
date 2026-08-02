defmodule ControlKeel.Bootstrap.LocalDefaults do
  @moduledoc """
  Single source of truth for provisioning the local-mode default org and
  workspace.

  In local CLI mode every session belongs to the Default Workspace, and the
  Default Workspace belongs to the Default Organization
  (1 org -> 1 workspace -> N sessions). Provisioning is a find-or-create: it is
  idempotent and safe to call at server boot, during `controlkeel setup`, and
  defensively right before session creation.

  In cloud / self-hosted mode this is a no-op — those runtimes own real orgs
  and memberships and must not receive a synthetic default org.
  """

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace

  @default_org_slug "default-organization"
  @default_workspace_slug "default-workspace"

  @doc "Slug of the reserved Default Organization."
  @spec default_org_slug :: String.t()
  def default_org_slug, do: @default_org_slug

  @doc "Slug of the reserved Default Workspace."
  @spec default_workspace_slug :: String.t()
  def default_workspace_slug, do: @default_workspace_slug

  @doc """
  Ensure the default org and workspace exist, returning
  `{:ok, {org, workspace}}`.

  Returns `{:ok, nil}` when not running in local mode (no-op for cloud /
  self-hosted). Idempotent: repeated calls reuse the existing rows and never
  duplicate. Race-safe: if a concurrent insert wins the slug, the loser
  refetches the existing row instead of erroring.
  """
  @spec ensure :: {:ok, {Accounts.Org.t(), Workspace.t()} | nil} | {:error, term()}
  def ensure do
    if local_mode?() do
      with {:ok, org} <- ensure_org(),
           {:ok, workspace} <- ensure_workspace(org) do
        {:ok, {org, workspace}}
      end
    else
      {:ok, nil}
    end
  end

  defp ensure_org do
    case Accounts.get_org_by_slug(@default_org_slug) do
      %Accounts.Org{} = org -> {:ok, org}
      nil -> create_org()
    end
  end

  defp create_org do
    case Accounts.create_org(%{name: "Default Organization", slug: @default_org_slug}) do
      {:ok, %Accounts.Org{} = org} ->
        {:ok, org}

      {:error, changeset} ->
        refetch_org_on_conflict(changeset)
    end
  end

  defp refetch_org_on_conflict(changeset) do
    if slug_conflict?(changeset) do
      case Accounts.get_org_by_slug(@default_org_slug) do
        %Accounts.Org{} = org -> {:ok, org}
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp ensure_workspace(org) do
    case Mission.get_workspace_by_slug(@default_workspace_slug) do
      %Workspace{} = workspace -> reconcile_workspace(workspace, org)
      nil -> create_workspace(org)
    end
  end

  defp reconcile_workspace(workspace, org) do
    cond do
      is_nil(workspace.org_id) ->
        backfill_workspace_org(workspace, org)

      workspace.org_id == org.id ->
        {:ok, workspace}

      true ->
        {:error, {:workspace_org_conflict, workspace.id, workspace.org_id, org.id}}
    end
  end

  defp backfill_workspace_org(workspace, org) do
    case Mission.update_workspace(workspace, %{org_id: org.id}) do
      {:ok, %Workspace{} = updated} -> {:ok, updated}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp create_workspace(org) do
    attrs = %{
      name: "Default Workspace",
      slug: @default_workspace_slug,
      industry: "general",
      agent: "claude",
      budget_cents: 0,
      compliance_profile: "general",
      status: "active",
      org_id: org.id
    }

    case Mission.create_workspace(attrs) do
      {:ok, %Workspace{} = workspace} ->
        {:ok, workspace}

      {:error, changeset} ->
        refetch_workspace_on_conflict(changeset, org)
    end
  end

  defp refetch_workspace_on_conflict(changeset, org) do
    if slug_conflict?(changeset) do
      case Mission.get_workspace_by_slug(@default_workspace_slug) do
        %Workspace{} = workspace -> reconcile_workspace(workspace, org)
        nil -> {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp slug_conflict?(changeset) do
    case Keyword.get(changeset.errors, :slug) do
      nil ->
        false

      {message, meta} when is_binary(message) ->
        message == "has already been taken" or Keyword.get(meta, :constraint) == :unique
    end
  end

  defp local_mode? do
    Application.get_env(
      :controlkeel,
      :local_defaults_local_mode_fn,
      &ControlKeel.Runtime.local?/0
    ).()
  end
end
