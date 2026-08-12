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
      the default.
    * **Workspaces:** if a single workspace exists, rename it to the Default
      Workspace and link it to the Default Org. If several exist, rename the
      **oldest** to the default and link it to the Default Org, then move every
      session (with its memory and analytics) into it.

  Leftover orgs/workspaces are NOT deleted by the migration itself. They are
  reported as **orphans**, and the caller decides via `cleanup:`:

    * `:keep` (default) — orphans stay as-is. They remain usable as source data
      for a future local-to-cloud migration and are never destroyed.
    * `:ask` — an interactive prompt is issued asking the user to delete all
      orphans or keep them. The prompt runs BEFORE the write transaction is
      opened (via a read-only orphan-count pre-pass), so no transaction lock is
      held across blocking stdin IO; a missing/non-"yes" answer keeps them.
    * `:delete` — all non-default workspaces and orgs are removed after
      sessions have been evacuated.

  Sessions and their children are always **evacuated** (moved, with memory and
  analytics repointed) before any workspace or org is deleted, so the
  `sessions.workspace_id on_delete: :delete_all` cascade never touches user
  data. The `workspaces.org_id` FK is `on_delete: :nilify_all`, so deleting
  non-default orgs only when their workspaces are already gone is safe.

  Local mode only. Triggered by `controlkeel update` (the new binary's update
  command). Idempotent: gated on the database not already matching the default
  architecture, so it runs at most once with real work per data shape and is a
  clean no-op on fresh installs, re-runs, and already-reconciled databases —
  retained orphans do NOT re-trigger it. Never blocks the caller at the
  database layer: `run/0` always returns `{:ok, _}` and logs failures instead
  of propagating them.
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

  The database needs reconciliation iff the database does NOT already match the
  default architecture, i.e. when any of these is true:

    * the Default Organization does not exist
    * the Default Workspace does not exist
    * the Default Workspace is not linked to the Default Organization
    * any session lives in a workspace other than the Default Workspace

  Satisfying the default architecture (including retained orphans) makes a
  repeat run a `:already_reconciled` no-op.

  ## Options

    * `:cleanup` — `:keep` (default) leaves orphan orgs/workspaces untouched;
      `:ask` prompts the user; `:delete` removes them after evacuation.
    * `:prompt` — a `fun/1` invoked for `cleanup: :ask`, receiving a summary
      map with `:orphan_workspaces`/`:orphan_orgs` counts and returning
      `:delete` or `:keep`. Defaults to a terminal prompt that keeps orphans
      unless the user answers `y`. Runs before the write transaction opens.

  Returns:

    * `{:ok, summary}`  — a map with `:sessions_moved`, `:orphan_workspaces`,
      `:orphan_orgs`, and (when orphans were deleted) `:removed_workspaces`/
      `:removed_orgs`
    * `{:ok, :already_reconciled}` — the database already matches the default architecture
    * `{:ok, :skipped_not_local}`  — not running in local mode
    * `{:ok, {:failed, reason}}`   — a handled failure (logged; caller unaffected)
  """
  @spec run(keyword()) :: {:ok, map() | atom() | {atom(), term()}}
  def run(opts \\ []) do
    if not local_mode?() do
      {:ok, :skipped_not_local}
    else
      {:ok, safe_run(opts)}
    end
  end

  defp safe_run(opts) do
    if not reconciliation_needed?() do
      :already_reconciled
    else
      perform(opts)
    end
  rescue
    exception ->
      log_failure(exception)
      {:failed, :exception}
  end

  defp perform(opts) do
    backup_database()

    orphan_decision = resolve_orphan_decision(opts)

    case Repo.transaction(fn ->
           {:ok, default_org} = reconcile_org()
           {:ok, default_workspace} = reconcile_workspace(default_org)

           summary = consolidate(default_org, default_workspace)
           apply_orphan_decision(orphan_decision, summary, default_org, default_workspace)
         end) do
      {:ok, summary} ->
        emit_summary(summary)
        summary

      {:error, reason} ->
        log_failure(reason)
        {:failed, :transaction}
    end
  end

  # ──────────────── gating ────────────────

  # The database needs reconciliation iff it is missing a linked default pair,
  # or still routes sessions outside the Default Workspace. Retained orphans do
  # not count as "needs reconciliation" — they are a stable, allowed shape.
  defp reconciliation_needed? do
    default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
    default_workspace = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

    cond do
      is_nil(default_org) -> true
      is_nil(default_workspace) -> true
      default_workspace.org_id != default_org.id -> true
      misplaced_sessions?(default_workspace) -> true
      true -> false
    end
  end

  # Any session in a workspace other than the Default Workspace.
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
  # (preserving its row identity).
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

  # Pick the Default Workspace and link it to the Default Org. If one with the
  # default slug already exists, reuse it (reparenting to the Default Org if
  # needed). Otherwise rename the OLDEST existing workspace into the default
  # and link it to the Default Org.
  defp reconcile_workspace(default_org) do
    default_slug = LocalDefaults.default_workspace_slug()

    case Mission.get_workspace_by_slug(default_slug) do
      %Workspace{} = workspace ->
        case workspace.org_id do
          org_id when org_id == default_org.id ->
            {:ok, workspace}

          _ ->
            Mission.update_workspace(workspace, %{org_id: default_org.id})
        end

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

  # ──────────────── consolidate (evacuate, never delete here) ────────────────

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
      # workspace that remains an orphan.
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

    %{
      sessions_moved: length(moved_session_ids),
      orphan_workspaces: count_orphan_workspaces(default_workspace),
      orphan_orgs: count_orphan_orgs(default_org)
    }
  end

  defp count_orphan_workspaces(default_workspace) do
    Repo.aggregate(
      from(w in Workspace, where: w.id != ^default_workspace.id),
      :count
    )
  end

  defp count_orphan_orgs(default_org) do
    Repo.aggregate(
      from(o in Org, where: o.id != ^default_org.id),
      :count
    )
  end

  # Pre-pass totals for the orphan decision. The reconcile step renames the
  # oldest row into the default (or reuses an existing default-slug row), so it
  # never changes the row counts — the post-consolidate orphan count is always
  # exactly `total - 1`.
  defp orphan_workspace_count do
    Repo.aggregate(Workspace, :count)
  end

  defp orphan_org_count do
    Repo.aggregate(Org, :count)
  end

  # ──────────────── orphan policy ────────────────

  # Resolves the orphan cleanup decision using a read-only pre-pass, BEFORE
  # the write transaction opens. `cleanup: :ask` runs its interactive prompt
  # here so no transaction (or its lock) is held open across blocking stdin
  # IO. The counts are derived from a full read; the subsequent transactional
  # reconcile never adds/removes org/workspace rows (it renames the oldest), so
  # the finite orphans (id != default) are exactly (total - 1). The decision
  # is then applied inside the same transaction as reconcile/consolidate.
  defp resolve_orphan_decision(opts) do
    case Keyword.get(opts, :cleanup, :keep) do
      :ask ->
        counts = %{
          orphan_workspaces: max(orphan_workspace_count() - 1, 0),
          orphan_orgs: max(orphan_org_count() - 1, 0)
        }

        if counts.orphan_workspaces == 0 and counts.orphan_orgs == 0 do
          :keep
        else
          prompt = Keyword.get(opts, :prompt, &default_prompt/1)
          prompt.(counts)
        end

      decision ->
        decision
    end
  end

  # Applies the caller's orphan cleanup decision after consolidation. Only ever
  # deletes rows that hold no sessions (sessions were evacuated above).
  defp apply_orphan_decision(:delete, summary, default_org, default_workspace) do
    remove_orphans(summary, default_org, default_workspace)
  end

  defp apply_orphan_decision(_keep, summary, _default_org, _default_workspace), do: summary

  defp remove_orphans(summary, default_org, default_workspace) do
    session_workspace_ids = from(s in Session, select: s.workspace_id)

    {workspaces_removed, _} =
      Repo.delete_all(
        from(w in Workspace,
          where: w.id != ^default_workspace.id and w.id not in subquery(session_workspace_ids)
        )
      )

    workspace_org_ids = from(w in Workspace, select: w.org_id)

    {orgs_removed, _} =
      Repo.delete_all(
        from(o in Org,
          where: o.id != ^default_org.id and o.id not in subquery(workspace_org_ids)
        )
      )

    summary
    |> Map.put(:removed_workspaces, workspaces_removed)
    |> Map.put(:removed_orgs, orgs_removed)
    |> Map.put(:orphan_workspaces, count_orphan_workspaces(default_workspace))
    |> Map.put(:orphan_orgs, count_orphan_orgs(default_org))
  end

  defp default_prompt(summary) do
    case IO.gets(
           "The update uses a single Default Organization and Default Workspace. " <>
             "#{summary.orphan_workspaces} leftover workspace(s) and " <>
             "#{summary.orphan_orgs} leftover org(s) can be deleted now or kept for " <>
             "local-to-cloud migration. Delete them now? [y/N] "
         ) do
      answer when is_binary(answer) ->
        case String.trim(answer) |> String.downcase() do
          value when value in ["y", "yes"] -> :delete
          _ -> :keep
        end

      _ ->
        :keep
    end
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
  def render(%{sessions_moved: sessions} = summary) do
    orphan_ws = Map.get(summary, :orphan_workspaces, 0)
    orphan_orgs = Map.get(summary, :orphan_orgs, 0)
    removed_ws = Map.get(summary, :removed_workspaces, 0)
    removed_orgs = Map.get(summary, :removed_orgs, 0)

    lines = [
      "Local data reconciliation:",
      "  Moved #{sessions} session(s) into the Default Workspace."
    ]

    lines =
      if removed_ws > 0 or removed_orgs > 0 do
        lines ++
          [
            "  Deleted #{removed_ws} leftover workspace(s) and " <>
              "#{removed_orgs} leftover org(s)."
          ]
      else
        lines
      end

    lines =
      if orphan_ws > 0 or orphan_orgs > 0 do
        lines ++
          [
            "  Left #{orphan_ws} leftover workspace(s) and " <>
              "#{orphan_orgs} leftover org(s) in place as orphans.",
            "  Local mode uses a single Default Workspace/Organization. " <>
              "Orphans are preserved for a future local-to-cloud migration; " <>
              "you can delete them with the interactive cleanup prompt."
          ]
      else
        lines
      end

    lines
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
  def to_payload(%{} = summary) do
    %{
      "status" => "completed",
      "sessions_moved" => Map.get(summary, :sessions_moved, 0),
      "orphan_workspaces" => Map.get(summary, :orphan_workspaces, 0),
      "orphan_orgs" => Map.get(summary, :orphan_orgs, 0),
      "removed_workspaces" => Map.get(summary, :removed_workspaces, 0),
      "removed_orgs" => Map.get(summary, :removed_orgs, 0)
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
        "moved #{summary.sessions_moved} session(s)"
    )

    if Map.get(summary, :orphan_workspaces, 0) > 0 or Map.get(summary, :orphan_orgs, 0) > 0 do
      Logger.warning(
        "[local-migration] left #{summary.orphan_workspaces} leftover workspace(s) " <>
          "and #{summary.orphan_orgs} leftover org(s) as orphans — kept for local-to-cloud migration."
      )
    end

    if Map.get(summary, :removed_workspaces, 0) > 0 or Map.get(summary, :removed_orgs, 0) > 0 do
      Logger.warning(
        "[local-migration] deleted #{summary.removed_workspaces} workspace(s) and " <>
          "#{summary.removed_orgs} org(s) after evacuating their sessions."
      )
    end
  end

  defp log_failure(exception) do
    require Logger

    message =
      case exception do
        %{__exception__: true} -> Exception.message(exception)
        other when is_binary(other) -> other
        other -> inspect(other)
      end

    Logger.warning("[local-migration] consolidation failed: #{message}")
  end
end
