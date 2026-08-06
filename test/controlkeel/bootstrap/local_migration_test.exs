defmodule ControlKeel.Bootstrap.LocalMigrationTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Analytics.Event, as: AnalyticsEvent
  alias ControlKeel.Bootstrap.LocalDefaults
  alias ControlKeel.Bootstrap.LocalMigration
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Session
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Repo

  setup do
    reset_migration_state!()
    :ok
  end

  describe "run/0 in local mode" do
    test "consolidates orphan workspaces into the default org/workspace" do
      ws_a = workspace_fixture(%{name: "Project A", slug: "project-a"})
      ws_b = workspace_fixture(%{name: "Project B", slug: "project-b"})
      session_a = session_fixture(%{workspace: ws_a})
      session_b = session_fixture(%{workspace: ws_b})

      assert is_nil(ws_a.org_id)
      assert is_nil(ws_b.org_id)
      sessions_before = Repo.aggregate(Session, :count)

      assert {:ok, summary} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      default_ws = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

      assert default_org
      assert default_ws
      assert default_ws.org_id == default_org.id

      # both sessions end up under the default workspace
      assert Repo.get(Session, session_a.id).workspace_id == default_ws.id
      assert Repo.get(Session, session_b.id).workspace_id == default_ws.id

      # the oldest workspace (ws_a) was repurposed into the default; the rest deleted
      assert Repo.get(Workspace, ws_a.id).slug == "default-workspace"
      refute Repo.get(Workspace, ws_b.id)

      # only the default org + workspace remain
      assert Repo.aggregate(Workspace, :count) == 1
      assert Repo.aggregate(Org, :count) == 1

      # zero sessions lost
      assert Repo.aggregate(Session, :count) == sessions_before
      assert summary.sessions_moved == 1
      assert summary.workspaces_removed == 1
    end

    test "with multiple orgs, the oldest is renamed to default and the rest are deleted" do
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org(%{name: "Org B", slug: "org-b"})
      {:ok, org_c} = Accounts.create_org(%{name: "Org C", slug: "org-c"})

      # org_a is oldest; it should become the default and keep its row identity.
      assert {:ok, summary} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

      assert default_org.id == org_a.id
      assert Repo.get(Accounts.Org, org_a.id).slug == LocalDefaults.default_org_slug()
      refute Repo.get(Accounts.Org, org_b.id)
      refute Repo.get(Accounts.Org, org_c.id)
      assert Repo.aggregate(Org, :count) == 1
      assert summary.orgs_removed == 2
    end

    test "repoints session-scoped memory and analytics onto the default workspace" do
      workspace = workspace_fixture(%{name: "Legacy", slug: "legacy-ws"})
      session = session_fixture(%{workspace: workspace})

      {:ok, memory} = insert_memory_record(session, workspace)
      {:ok, event} = insert_analytics_event(session, workspace)

      assert {:ok, _} = LocalMigration.run()

      default_ws = Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())

      assert Repo.get(MemoryRecord, memory.id).workspace_id == default_ws.id
      assert Repo.get(AnalyticsEvent, event.id).workspace_id == default_ws.id
    end

    test "claims an existing default-workspace slug for the default org" do
      {:ok, other_org} =
        Accounts.create_org(%{name: "Other", slug: "other-org"})

      {:ok, existing_default} =
        Mission.create_workspace(%{
          name: "Default Workspace",
          slug: LocalDefaults.default_workspace_slug(),
          industry: "general",
          agent: "claude",
          budget_cents: 0,
          compliance_profile: "general",
          status: "active",
          org_id: other_org.id
        })

      session = session_fixture(%{workspace: existing_default})

      assert {:ok, _} = LocalMigration.run()

      default_org = Accounts.get_org_by_slug(LocalDefaults.default_org_slug())

      # the pre-existing default-workspace was claimed for the default org
      assert Repo.get(Workspace, existing_default.id).org_id == default_org.id
      # the other org was the only org, so it was renamed into the default (not deleted)
      assert Repo.get(Accounts.Org, other_org.id).slug == LocalDefaults.default_org_slug()
      # the session survived and stays under the (now claimed) default workspace
      assert Repo.get(Session, session.id).workspace_id == existing_default.id
    end

    test "is idempotent: a second run is a no-op once the DB matches the architecture" do
      workspace = workspace_fixture(%{name: "Solo", slug: "solo-ws"})
      session_fixture(%{workspace: workspace})

      assert {:ok, %{} = first} = LocalMigration.run()
      # the single workspace was renamed into the default in place, so the
      # session already lives in it — nothing to move.
      assert first.sessions_moved == 0

      # After consolidation the DB has a single default org/workspace, so the
      # data-shape gate short-circuits the second run.
      assert {:ok, :already_reconciled} = LocalMigration.run()
    end

    test "is a no-op when the database already matches the default architecture" do
      {:ok, {_org, _workspace}} = ControlKeel.Bootstrap.LocalDefaults.ensure()

      sessions_before = Repo.aggregate(Session, :count)
      orgs_before = Repo.aggregate(Org, :count)
      workspaces_before = Repo.aggregate(Workspace, :count)

      assert {:ok, :already_reconciled} = LocalMigration.run()

      # nothing created, moved, or deleted
      assert Repo.aggregate(Session, :count) == sessions_before
      assert Repo.aggregate(Org, :count) == orgs_before
      assert Repo.aggregate(Workspace, :count) == workspaces_before
    end

    test "provisions the defaults when they are missing" do
      # reset_migration_state! removed the default org/workspace. With no legacy
      # sessions either, the gate still fires on "defaults missing" and creates
      # them, consolidating nothing.
      assert {:ok, summary} = LocalMigration.run()

      assert Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      assert Mission.get_workspace_by_slug(LocalDefaults.default_workspace_slug())
      assert summary.sessions_moved == 0
      assert summary.workspaces_removed == 0
      assert summary.orgs_removed == 0
    end
  end

  describe "run/0 outside local mode" do
    test "is a no-op and touches nothing" do
      Application.put_env(:controlkeel, :local_defaults_local_mode_fn, fn -> false end)
      on_exit(fn -> Application.delete_env(:controlkeel, :local_defaults_local_mode_fn) end)

      workspace = workspace_fixture(%{name: "Untouched", slug: "untouched-ws"})
      session_fixture(%{workspace: workspace})

      assert {:ok, :skipped_not_local} = LocalMigration.run()

      # no default org/workspace created, no workspaces deleted
      refute Accounts.get_org_by_slug(LocalDefaults.default_org_slug())
      assert Repo.get(Workspace, workspace.id)
    end
  end

  describe "render/1 and to_payload/1 (update notification)" do
    test "render reports counts when reconciliation did work" do
      lines =
        LocalMigration.render(%{
          sessions_moved: 3,
          workspaces_removed: 2,
          orgs_removed: 1
        })

      assert Enum.join(lines, "\n") =~ "Moved 3 session(s) into the Default Workspace."
      assert Enum.join(lines, "\n") =~ "Removed 2 workspace(s)."
      assert Enum.join(lines, "\n") =~ "Removed 1 org(s)."
    end

    test "render flags unexpected cardinality" do
      lines =
        LocalMigration.render(%{sessions_moved: 0, workspaces_removed: 3, orgs_removed: 2})

      assert Enum.any?(lines, &String.contains?(&1, "single org/workspace"))
    end

    test "render stays quiet when nothing needed reconciliation" do
      assert LocalMigration.render(:already_reconciled) == [
               "Local data already matches the current architecture — nothing to reconcile."
             ]

      assert LocalMigration.render(:skipped_not_local) == []
    end

    test "to_payload is JSON-safe for every result shape" do
      assert LocalMigration.to_payload(%{
               sessions_moved: 1,
               workspaces_removed: 1,
               orgs_removed: 0
             }) == %{
               "status" => "completed",
               "sessions_moved" => 1,
               "workspaces_removed" => 1,
               "orgs_removed" => 0
             }

      assert LocalMigration.to_payload(:already_reconciled) == %{"status" => "already_reconciled"}
      assert LocalMigration.to_payload(:skipped_not_local) == %{"status" => "skipped_not_local"}
      assert LocalMigration.to_payload({:failed, :exception}) == %{"status" => "failed"}

      # every payload must be Jason-encodable (no tuples/atoms leaking)
      for result <- [
            %{sessions_moved: 1, workspaces_removed: 1, orgs_removed: 0},
            :already_reconciled,
            :skipped_not_local,
            {:failed, :exception}
          ] do
        assert {:ok, _} = Jason.encode(LocalMigration.to_payload(result))
      end
    end
  end

  # ──────────────── helpers ────────────────

  # Each test must start from a clean slate: the shared test database retains
  # the default org/workspace from a previous test (tests run serially).
  # delete_all lets the DB cascade handle children; the current test's orphan
  # fixtures are created after this reset, so they are untouched.
  defp reset_migration_state! do
    Repo.delete_all(
      from(w in Workspace, where: w.slug == ^LocalDefaults.default_workspace_slug())
    )

    Repo.delete_all(from(o in Accounts.Org, where: o.slug == ^LocalDefaults.default_org_slug()))

    :ok
  end

  defp insert_memory_record(session, workspace) do
    %MemoryRecord{}
    |> MemoryRecord.changeset(%{
      workspace_id: workspace.id,
      session_id: session.id,
      record_type: "decision",
      title: "recorded note",
      summary: "summary",
      body: "body",
      tags: [],
      source_type: "test",
      source_id: "src-#{System.unique_integer([:positive])}",
      metadata: %{}
    })
    |> Repo.insert()
  end

  defp insert_analytics_event(session, workspace) do
    %AnalyticsEvent{}
    |> AnalyticsEvent.changeset(%{
      event: "tool.called",
      source: "test",
      metadata: %{},
      happened_at: DateTime.utc_now() |> DateTime.truncate(:second),
      session_id: session.id,
      workspace_id: workspace.id
    })
    |> Repo.insert()
  end
end
