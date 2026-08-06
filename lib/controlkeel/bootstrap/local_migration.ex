defmodule ControlKeel.Bootstrap.LocalMigration do
  @moduledoc """
  One-time reconciliation of pre-existing orgs/workspaces into the local-mode
  default hierarchy.

  Before default org/workspace provisioning existed, every local session launch
  created a fresh orphan workspace (`org_id` nil) named after the project —
  invisible to users (no UI/CLI surface) and unattached to any org. This
  migration consolidates that legacy data into a single
  `Default Organization` -> `Default Workspace` -> N sessions.

  ## Reconciliation policy

  Rather than creating new default rows and discarding the originals, the
  migration **repurposes the oldest existing rows** to preserve their identity:

    * **Orgs:** if a single org exists, rename it to the Default Organization
      (name + slug). If several exist, rename the **oldest** (first created) to
      the default and delete the rest.
    * **Workspaces:** if a single workspace exists, rename it to the Default
      Workspace and link it to the Default Org. If several exist, rename the
      **oldest** to the default, link it to the Default Org, move every session
      into it, then delete the rest.

  Safe by construction: sessions and their children are **evacuated** (moved,
  with their memory and analytics repointed) before any workspace is deleted, so
  the `sessions.workspace_id on_delete: :delete_all` cascade never touches user
  data. The `workspaces.org_id` FK is `on_delete: :nilify_all`, so deleting
  non-default orgs is safe.

  Local mode only. Triggered by `controlkeel update` (the new binary's update
  command). Idempotent: gated on the database not already matching the default
  architecture, so it runs at most once with real work and is a clean no-op on
  fresh installs, re-runs, and already-reconciled databases. Never blocks the
  caller — `run/0` always returns `{:ok, _}` and logs failures instead of
  propagating them.
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

  @doc """
  Run the local data reconciliation.

  Triggered by `controlkeel update` (local mode only). It runs only when the
  database does NOT already match the default architecture — i.e. when any of
  these is true:

    * the Default Organization does not exist
    * the Default Workspace does not exist
    * more than one org exists
    * more than one workspace exists
    * any session lives in a workspace other than the Default Workspace

  Returns:

    * `{:ok, summary}`  — a map of counts (`:sessions_moved`, `:workspaces_removed`, `:orgs_removed`)
    * `{:ok, :already_reconciled}` — the database already matches the default architecture
    * `{:ok, :skipped_not_local}`  — not running in local mode
    * `{:ok, {:failed, reason}}`   — a handled failure (logged; caller unaffected)
  """
  @spec run :: {:ok, map() | atom() | {atom(), term()}}
  def run do
    if not local_mode?() do
      {:ok, :skipped_not_local}
    else
      {:ok, safe_run()}
    end
  end

  defp safe_run do
    if not reconciliation_needed?() do
      :already_reconciled
    else
      perform()
    end
  rescue
    exception ->
      log_failure(exception)
      {:failed, :exception}
  end

  defp perform do
    backup_database()

    {:ok, default_org} = reconcile_org()
    {:ok, default_workspace} = reconcile_workspace(default_org)

    summary = consolidate(default_org, default_workspace)

    emit_summary(summary)
    summary
  end

  # ──────────────── gating ────────────────

  # The database needs reconciliation iff it does NOT already match the single
  # default hierarchy: exactly one Default Org, exactly one Default Workspace,
  # and every session under that workspace. Each condition below is a signal
  # that the DB still holds legacy data (or has not yet been provisioned).
  defp reconciliation_needed? do
    default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
    default_workspace = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

    cond do
      is_nil(default_org) -> true
      is_nil(default_workspace) -> true
      Repo.aggregate(Org, :count) > 1 -> true
      Repo.aggregate(Workspace, :count) > 1 -> true
      misplaced_sessions?(default_workspace) -> true
      true -> false
    end
  end

  defp misplaced_sessions?(default_workspace) do
    Repo.aggregate(
      from(s in Session, where: s.workspace_id != ^default_workspace.id),
      :count
    ) > 0
  end

  # ──────────────── local mode ────────────────

  defp local_mode? do
    Application.get_env(
      :controlkeel,
      :local_defaults_local_mode_fn,
      &ControlKeel.Runtime.local?/0
    ).()
  end

  # ──────────────── reconcile (rename oldest into default) ────────────────

  # Pick the Default Org. If one with the default slug already exists, reuse it
  # (idempotent). Otherwise rename the OLDEST existing org into the default
  # (preserving its row identity); deletion of the remaining orgs happens later
  # in `consolidate/2` once workspaces/sessions have been evacuated.
  defp reconcile_org do
    default_slug = LocalDefaults.default_org_slug()

    case Accounts.get_org_by_slug(default_slug) do
      %Org{} = org ->
        {:ok, org}

      nil ->
        orgs = Repo.all(from(o in Org, order_by: [asc: o.inserted_at, asc: o.id]))

        case orgs do
          [] ->
            Accounts.create_org(%{name: "Default Organization", slug: default_slug})

          [oldest | _rest] ->
            Org.changeset(oldest, %{name: "Default Organization", slug: default_slug})
            |> Repo.update()
        end
    end
  end

  # Pick the Default Workspace. If one with the default slug already exists,
  # reuse it (reparenting to the Default Org if needed). Otherwise rename the
  # OLDEST existing workspace into the default and link it to the Default Org;
  # deletion of the remaining workspaces happens later in `consolidate/2` after
  # sessions are evacuated into the default workspace.
  defp reconcile_workspace(default_org) do
    default_slug = LocalDefaults.default_workspace_slug()

    case Mission.get_workspace_by_slug(default_slug) do
      %Workspace{org_id: org_id} = workspace when org_id == default_org.id ->
        {:ok, workspace}

      %Workspace{} = workspace ->
        Mission.update_workspace(workspace, %{org_id: default_org.id})

      nil ->
        workspaces = Repo.all(from(w in Workspace, order_by: [asc: w.inserted_at, asc: w.id]))

        case workspaces do
          [] ->
            Mission.create_workspace(%{
              name: "Default Workspace",
              slug: default_slug,
              industry: "general",
              agent: "claude",
              budget_cents: 0,
              compliance_profile: "general",
              status: "active",
              org_id: default_org.id
            })

          [oldest | _rest] ->
            Mission.update_workspace(oldest, %{
              name: "Default Workspace",
              slug: default_slug,
              org_id: default_org.id
            })
        end
    end
  end

  # ──────────────── consolidate ────────────────

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

  # ──────────────── rendering + observability ────────────────

  @doc """
  Human-readable CLI lines for a `run/0` result, for the `controlkeel update`
  output. Used so the update command can notify the user of what changed.
  """
  @spec render(term()) :: [String.t()]
  def render(%{sessions_moved: sessions, workspaces_removed: workspaces, orgs_removed: orgs}) do
    lines = [
      "Local data reconciliation:",
      "  Moved #{sessions} session(s) into the Default Workspace.",
      "  Removed #{workspaces} workspace(s).",
      "  Removed #{orgs} org(s)."
    ]

    if workspaces > 1 or orgs > 1 do
      lines ++
        ["  Note: local mode expects a single org/workspace — review if unexpected."]
    else
      lines
    end
  end

  def render(:already_reconciled),
    do: ["Local data already matches the current architecture — nothing to reconcile."]

  def render(:skipped_not_local), do: []

  def render({:failed, _}),
    do: ["Local data reconciliation failed; see logs. No data was modified."]

  def render(_), do: []

  @doc """
  JSON-safe map form of a `run/0` result, for the `controlkeel update --json`
  payload. Avoids encoding raw atoms/tuples directly.
  """
  @spec to_payload(term()) :: map()
  def to_payload(%{sessions_moved: s, workspaces_removed: w, orgs_removed: o}) do
    %{
      "status" => "completed",
      "sessions_moved" => s,
      "workspaces_removed" => w,
      "orgs_removed" => o
    }
  end

  def to_payload(:already_reconciled), do: %{"status" => "already_reconciled"}
  def to_payload(:skipped_not_local), do: %{"status" => "skipped_not_local"}
  def to_payload({:failed, _}), do: %{"status" => "failed"}
  def to_payload(_), do: %{"status" => "unknown"}

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
