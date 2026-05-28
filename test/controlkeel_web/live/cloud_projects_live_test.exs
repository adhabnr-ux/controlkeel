defmodule ControlKeelWeb.CloudProjectsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.WorkspaceKeyRegistry
  alias ControlKeel.Repo

  describe "cloud project show page — packages card (CK-CLOUD-OBS-001)" do
    test "shows 'not yet linked' message for unbound enrollment", %{conn: conn} do
      key = enroll_key(%{org_id: nil, mission_workspace_id: nil})

      {:ok, _view, html} = live(conn, ~p"/cloud/projects/#{key.workspace_id}")

      assert html =~ "Cloud run packages"
      assert html =~ "not yet linked to a project"
    end

    test "shows 'no runs yet' message for linked but empty workspace", %{conn: conn} do
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "member")
      mws = insert_mission_workspace(org)
      key = enroll_key(%{org_id: org.id, mission_workspace_id: mws.id})

      conn = session_conn(conn, user.id, org.id)
      {:ok, _view, html} = live(conn, ~p"/cloud/projects/#{key.workspace_id}")

      assert html =~ "Cloud run packages"
      assert html =~ "No cloud runs handed off yet"
    end

    test "renders package rows with runtime, status, revision, budget", %{conn: conn} do
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "member")
      mws = insert_mission_workspace(org)
      key = enroll_key(%{org_id: org.id, mission_workspace_id: mws.id})

      session = ControlKeel.MissionFixtures.session_fixture(%{workspace: mws})
      task = ControlKeel.MissionFixtures.task_fixture(%{session: session})

      {:ok, _pkg, _token} =
        RuntimeContext.create_package(%{
          workspace_id: mws.id,
          session_id: session.id,
          task_id: task.id,
          runtime_target: "devin",
          budget_cents_allocated: 500,
          branch: "main",
          commit_sha: "abc123def4567890",
          repo_url: "git@github.com:acme/widget.git",
          user_id: user.id
        })

      conn = session_conn(conn, user.id, org.id)
      {:ok, _view, html} = live(conn, ~p"/cloud/projects/#{key.workspace_id}")

      assert html =~ "devin"
      assert html =~ "main@abc123d"
      assert html =~ "500"
      assert html =~ "pending"
    end
  end

  # ─────────────── helpers ───────────────

  defp session_conn(conn, user_id, org_id) do
    conn
    |> Plug.Test.init_test_session(%{
      "current_user_id" => user_id,
      "current_org_id" => org_id
    })
  end

  defp insert_org do
    s = "org-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: s, slug: s, status: "active"})
      |> Repo.insert()

    org
  end

  defp insert_user do
    {:ok, user} =
      %Accounts.User{}
      |> Accounts.User.changeset(%{
        email: "u-#{System.unique_integer([:positive])}@example.com",
        status: "active"
      })
      |> Repo.insert()

    user
  end

  defp insert_active_membership(user_id, org_id, role) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, m} =
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user_id,
        org_id: org_id,
        role: role,
        status: "active",
        accepted_at: now
      })
      |> Repo.insert()

    m
  end

  defp insert_mission_workspace(org) do
    n = Integer.to_string(System.unique_integer([:positive]))

    {:ok, ws} =
      %ControlKeel.Mission.Workspace{}
      |> ControlKeel.Mission.Workspace.changeset(%{
        name: "Project #{n}",
        slug: "project-#{n}",
        org_id: org.id,
        industry: "technology",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "baseline",
        status: "active"
      })
      |> Repo.insert()

    ws
  end

  defp enroll_key(overrides) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    pub_b64 = Base.encode64(pub)
    fp = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(
        %{
          workspace_id:
            "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
          public_key: pub_b64,
          algorithm: "ed25519",
          fingerprint: fp,
          name: "test"
        },
        overrides
      )

    {:ok, key} = WorkspaceKeyRegistry.enroll(attrs)
    key
  end
end
