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

      # both sessions moved into the default workspace
      assert Repo.get(Session, session_a.id).workspace_id == default_ws.id
      assert Repo.get(Session, session_b.id).workspace_id == default_ws.id

      # orphan workspaces deleted
      refute Repo.get(Workspace, ws_a.id)
      refute Repo.get(Workspace, ws_b.id)

      # only the default org + workspace remain
      assert Repo.aggregate(Workspace, :count) == 1
      assert Repo.aggregate(Org, :count) == 1

      # zero sessions lost
      assert Repo.aggregate(Session, :count) == sessions_before
      assert summary.sessions_moved == 2
      assert summary.workspaces_removed == 2
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
      # the other org is now empty and removed
      refute Repo.get(Accounts.Org, other_org.id)
      # the session survived and stays under the (now claimed) default workspace
      assert Repo.get(Session, session.id).workspace_id == existing_default.id
    end

    test "is idempotent: a second run is a no-op" do
      workspace = workspace_fixture(%{name: "Solo", slug: "solo-ws"})
      session_fixture(%{workspace: workspace})

      assert {:ok, %{} = first} = LocalMigration.run()
      assert first.sessions_moved == 1

      assert {:ok, :skipped_already_run} = LocalMigration.run()
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

  # ──────────────── helpers ────────────────

  # Each test must start from a clean slate: the shared test database retains
  # the default org/workspace/marker from a previous test (tests run serially).
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
