defmodule ControlKeel.Bootstrap.LocalMigration do
  @moduledoc """
  One-time reconciliation of pre-existing orgs/workspaces into the local-mode
  default hierarchy.

  Before default org/workspace provisioning existed, every local session launch
  created a fresh orphan workspace (`org_id` nil) named after the project —
  invisible to users (no UI/CLI surface) and unattached to any org. This
  migration consolidates that legacy data into a single
  `Default Organization` -> `Default Workspace` -> N sessions, deleting the
  empty workspace/org shells.

  Safe by construction: sessions and their children are **evacuated** (moved,
  with their memory and analytics repointed) before any workspace is deleted, so
  the `sessions.workspace_id on_delete: :delete_all` cascade never touches user
  data. The `workspaces.org_id` FK is `on_delete: :nilify_all`, so deleting
  non-default orgs is safe.

  Local mode only. Idempotent (marker-gated). Never blocks boot — `run/0`
  always returns `{:ok, _}` and logs failures instead of propagating them.
  """

  import Ecto.Query

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Analytics.Event, as: AnalyticsEvent
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Repo

  @migration_version 1

  @doc """
  Run the one-time local consolidation.

  Returns `{:ok, summary}` on success (a map of counts), or one of
  `{:ok, :skipped_not_local}`, `{:ok, :skipped_already_run}`, or
  `{:ok, {:failed, reason}}` on a handled failure. Always returns `{:ok, _}` so
  callers (boot/setup) can ignore the result.
  """
  @spec run :: {:ok, map() | atom() | {atom(), term()}}
  def run do
    cond do
      not local_mode?() ->
        {:ok, :skipped_not_local}

      marker_set?() ->
        {:ok, :skipped_already_run}

      true ->
        {:ok, safe_perform()}
    end
  end

  defp safe_perform do
    perform()
  rescue
    exception ->
      log_failure(exception)
      {:failed, :exception}
  end

  defp perform do
    backup_database()

    {:ok, default_org} = ensure_default_org()
    {:ok, default_workspace} = ensure_default_workspace(default_org)

    summary = consolidate(default_org, default_workspace)

    set_marker(default_org)
    emit_summary(summary)
    summary
  end

  # ──────────────── gating + marker ────────────────

  defp local_mode? do
    Application.get_env(
      :controlkeel,
      :local_defaults_local_mode_fn,
      &ControlKeel.Runtime.local?/0
    ).()
  end

  defp marker_set? do
    case Accounts.get_org_by_slug(LocalDefaults.default_org_slug()) do
      %Org{settings: settings} when is_map(settings) ->
        version = settings["local_consolidation_version"]
        is_integer(version) and version >= @migration_version

      _ ->
        false
    end
  end

  defp set_marker(%Org{} = org) do
    updated_settings =
      (org.settings || %{})
      |> Map.put("local_consolidation_version", @migration_version)

    org
    |> Ecto.Changeset.change(settings: updated_settings)
    |> Repo.update()
  end

  # ──────────────── defaults ────────────────

  defp ensure_default_org do
    case Accounts.get_org_by_slug(LocalDefaults.default_org_slug()) do
      %Org{} = org ->
        {:ok, org}

      nil ->
        Accounts.create_org(%{
          name: "Default Organization",
          slug: LocalDefaults.default_org_slug()
        })
    end
  end

  # The migration CLAIMS an existing `default-workspace` row for the default org
  # (reparent), unlike LocalDefaults.ensure/0 which treats a different-org
  # default-workspace as a hard conflict. Intentional: the migration is the
  # consolidating authority and runs once.
  defp ensure_default_workspace(default_org) do
    case Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug()) do
      %Workspace{org_id: org_id} = workspace when org_id == default_org.id ->
        {:ok, workspace}

      %Workspace{} = workspace ->
        Mission.update_workspace(workspace, %{org_id: default_org.id})

      nil ->
        Mission.create_workspace(%{
          name: "Default Workspace",
          slug: LocalDefaults.default_workspace_slug(),
          industry: "general",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: default_org.id
        })
    end
  end

  # ──────────────── consolidate (one transaction) ────────────────

  defp consolidate(default_org, default_workspace) do
    moved_session_ids =
      Repo.all(
        from(s in Session,
          where: s.workspace_id != ^default_workspace.id,
          select: s.id
        )
      )

    if moved_session_ids != [] do
      # Repoint session-scoped children BEFORE moving the sessions, so they
      # follow the session onto the default workspace instead of stranding on a
      # workspace we are about to delete.
      Repo.update_all(
        from(m in MemoryRecord, where: m.session_id in ^moved_session_ids),
        set: [workspace_id: default_workspace.id]
      )

      Repo.update_all(
        from(a in AnalyticsEvent, where: a.session_id in ^moved_session_ids),
        set: [workspace_id: default_workspace.id]
      )

      Repo.update_all(
        from(s in Session, where: s.workspace_id != ^default_workspace.id),
        set: [workspace_id: default_workspace.id]
      )
    end

    # Hard-delete empty non-default workspaces. After the move only the default
    # workspace holds sessions, so this removes the orphan shells. Cascades hit
    # only disposable workspace config (agents, github repos, baselines, tool
    # policies, workspace-only memory) — never sessions.
    session_workspace_ids = from(s in Session, select: s.workspace_id)

    {workspaces_removed, _} =
      Repo.delete_all(
        from(w in Workspace,
          where: w.id != ^default_workspace.id and w.id not in subquery(session_workspace_ids)
        )
      )

    # Hard-delete empty non-default orgs. After the workspace cleanup only the
    # default workspace remains (under the default org), so every other org is
    # unreferenced. org_id FK is nilify_all, so this is safe regardless.
    workspace_org_ids = from(w in Workspace, select: w.org_id)

    {orgs_removed, _} =
      Repo.delete_all(
        from(o in Org,
          where: o.id != ^default_org.id and o.id not in subquery(workspace_org_ids)
        )
      )

    %{
      sessions_moved: length(moved_session_ids),
      workspaces_removed: workspaces_removed,
      orgs_removed: orgs_removed
    }
  end

  # ──────────────── backup (best-effort) ────────────────

  defp backup_database do
    if backup_enabled?() do
      do_backup()
    else
      :ok
    end
  end

  # Skip in the test environment (Mix is loaded and reports :test): there is no
  # real data to protect, and writing backups would pollute priv/repo. In a
  # release Mix is absent, so this guard is a no-op there and backups run.
  defp backup_enabled? do
    not (Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test)
  end

  defp do_backup do
    db_path =
      :controlkeel
      |> Application.get_env(ControlKeel.Repo.Local, [])
      |> Keyword.get(:database)

    if is_binary(db_path) and File.exists?(db_path) do
      stamp =
        DateTime.utc_now()
        |> DateTime.to_iso8601()
        |> String.replace(~r/[^0-9a-zA-Z]/, "")

      for suffix <- ["", "-wal", "-shm"] do
        source = db_path <> suffix
        dest = db_path <> ".pre-local-defaults-" <> stamp <> suffix

        if File.exists?(source) do
          File.cp(source, dest)
        end
      end
    end

    :ok
  end

  # ──────────────── observability ────────────────

  defp emit_summary(summary) do
    require Logger

    Logger.info(
      "[local-migration] consolidated local data into the default org/workspace: " <>
        "moved #{summary.sessions_moved} session(s), " <>
        "removed #{summary.workspaces_removed} workspace(s), " <>
        "removed #{summary.orgs_removed} org(s)."
    )

    if summary.workspaces_removed > 1 or summary.orgs_removed > 1 do
      Logger.warning(
        "[local-migration] local mode expects a single org/workspace; " <>
          "removed #{summary.workspaces_removed} workspace(s) and #{summary.orgs_removed} org(s)."
      )
    end
  end

  defp log_failure(exception) do
    require Logger
    Logger.warning("[local-migration] consolidation failed: #{Exception.message(exception)}")
  end
end
