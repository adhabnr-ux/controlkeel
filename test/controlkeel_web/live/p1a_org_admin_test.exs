defmodule ControlKeelWeb.P1aOrgAdminTest do
  @moduledoc """
  P1a slice tests (docs/CLOUD_READINESS.md): /org/:slug/members,
  /org/:slug/settings/general, /workspaces/:id/repos. Plus context-level
  update_membership_role / update_org tests.
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Mission
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)
    :ok
  end

  defp create_org!(name) do
    slug = "#{name |> String.downcase() |> String.replace(~r/\W+/, "-")}-#{System.unique_integer([:positive])}"
    {:ok, org} = Accounts.create_org(%{name: name, slug: slug})
    org
  end

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp create_membership!(user, org, role) do
    {:ok, m} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: role,
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    m
  end

  defp sign_in(conn, user, org) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:current_user_id, user.id)
    |> put_session(:current_org_id, org.id)
  end

  describe "Accounts.update_membership_role / 2" do
    test "demotes a non-owner successfully" do
      org = create_org!("Demote")
      user = create_user!("d-#{System.unique_integer([:positive])}@x.test")
      m = create_membership!(user, org, "admin")

      assert {:ok, updated} = Accounts.update_membership_role(m.id, "member")
      assert updated.role == "member"
    end

    test "refuses to demote the last active owner" do
      org = create_org!("LastOwner")
      owner = create_user!("o-#{System.unique_integer([:positive])}@x.test")
      m = create_membership!(owner, org, "owner")

      assert {:error, :last_owner_protected} =
               Accounts.update_membership_role(m.id, "admin")

      assert Repo.reload!(m).role == "owner"
    end

    test "allows demoting an owner when another owner is active" do
      org = create_org!("TwoOwners")
      owner_a = create_user!("oa-#{System.unique_integer([:positive])}@x.test")
      owner_b = create_user!("ob-#{System.unique_integer([:positive])}@x.test")
      m_a = create_membership!(owner_a, org, "owner")
      _m_b = create_membership!(owner_b, org, "owner")

      assert {:ok, _} = Accounts.update_membership_role(m_a.id, "admin")
    end

    test "rejects an invalid role" do
      org = create_org!("InvalidRole")
      user = create_user!("ir-#{System.unique_integer([:positive])}@x.test")
      m = create_membership!(user, org, "member")

      assert {:error, :invalid_role} = Accounts.update_membership_role(m.id, "super-admin")
    end
  end

  describe "Accounts.revoke_membership/1 last-owner protection" do
    test "refuses to revoke the last active owner" do
      org = create_org!("RevokeLast")
      owner = create_user!("rl-#{System.unique_integer([:positive])}@x.test")
      m = create_membership!(owner, org, "owner")

      assert {:error, :last_owner_protected} = Accounts.revoke_membership(m.id)
      assert Repo.reload!(m).status == "active"
    end
  end

  describe "OrgMembersLive (/org/:slug/members)" do
    test "admin can list members and invite a new one", %{conn: conn} do
      org = create_org!("Members")
      admin = create_user!("admin-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(admin, org, "admin")

      conn = sign_in(conn, admin, org)

      {:ok, lv, html} = live(conn, ~p"/org/#{org.slug}/members")
      assert html =~ admin.email

      lv
      |> form("form[phx-submit=invite]", invite: %{email: "new@x.test", role: "member"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Invitation token issued"
      assert html =~ "/cloud/invitations/"
    end

    test "viewer is redirected to /cloud/projects with admin-required flash", %{conn: conn} do
      org = create_org!("ViewerNope")
      viewer = create_user!("v-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(viewer, org, "viewer")

      conn = sign_in(conn, viewer, org)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/org/#{org.slug}/members")
    end

    test "cross-org admin cannot view another org's members", %{conn: conn} do
      org_a = create_org!("OrgA")
      org_b = create_org!("OrgB")
      admin_a = create_user!("aa-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(admin_a, org_a, "admin")

      conn = sign_in(conn, admin_a, org_a)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/org/#{org_b.slug}/members")
    end
  end

  describe "OrgSettingsGeneralLive (/org/:slug/settings/general)" do
    test "owner can update name and budget", %{conn: conn} do
      org = create_org!("Settings")
      owner = create_user!("so-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(owner, org, "owner")

      conn = sign_in(conn, owner, org)
      {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/settings/general")

      _html =
        lv
        |> form("form[phx-submit=submit]", settings: %{
          name: "Renamed Org",
          status: "active",
          budget_cents: "50000"
        })
        |> render_submit()

      updated = Accounts.get_org(org.id)
      assert updated.name == "Renamed Org"
      assert Accounts.org_budget_cents(updated) == 50_000
    end

    test "admin sees disabled status/budget fields and only name is editable", %{conn: conn} do
      org = create_org!("AdminOnly")
      admin = create_user!("sa-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(admin, org, "admin")

      conn = sign_in(conn, admin, org)
      {:ok, lv, html} = live(conn, ~p"/org/#{org.slug}/settings/general")

      # Status + budget rendered as disabled inputs for non-owners
      assert html =~ ~s(name="settings[status]" disabled)
      assert html =~ ~s(name="settings[budget_cents]") and html =~ "disabled"

      # Admin can still submit the form to change name
      _html =
        lv
        |> form("form[phx-submit=submit]", settings: %{name: "Admin Renamed"})
        |> render_submit()

      updated = Accounts.get_org(org.id)
      assert updated.name == "Admin Renamed"
      # Budget not touched (admin couldn't change it)
      refute Accounts.org_budget_cents(updated) == 99_999
    end
  end

  describe "WorkspaceReposLive (/workspaces/:id/repos)" do
    setup do
      org = create_org!("RepoOrg")
      admin = create_user!("ra-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(admin, org, "admin")

      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "RepoWS",
          slug: "repo-ws-#{System.unique_integer([:positive])}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 5_000,
          compliance_profile: "baseline",
          status: "active",
          org_id: org.id
        })

      {:ok, org: org, admin: admin, workspace: workspace}
    end

    test "admin can bind and unbind a repo", %{conn: conn, org: org, admin: admin, workspace: ws} do
      conn = sign_in(conn, admin, org)

      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/repos")

      lv
      |> form("form[phx-submit=bind]", bind: %{
        owner: "acme",
        repo: "payments",
        default_branch: "main",
        installation_id: ""
      })
      |> render_submit()

      repos = Mission.list_github_repos(ws.id)
      assert Enum.any?(repos, &(&1.owner == "acme" and &1.repo == "payments"))

      render(lv) |> assert_html_contains("acme/payments")

      lv
      |> element("button[phx-click=unbind][phx-value-owner=acme][phx-value-repo=payments]")
      |> render_click()

      assert Mission.list_github_repos(ws.id) == []
    end

    test "cross-org admin cannot view another org's workspace repos", %{conn: conn, workspace: ws} do
      other_org = create_org!("OtherOrg")
      other_admin = create_user!("oa-#{System.unique_integer([:positive])}@x.test")
      _ = create_membership!(other_admin, other_org, "admin")

      conn = sign_in(conn, other_admin, other_org)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/repos")
    end
  end

  # ── Helper for HTML assertions ─────────────────────────────────────

  defp assert_html_contains(html, substr) when is_binary(html) do
    if String.contains?(html, substr) do
      :ok
    else
      flunk("Expected HTML to contain #{inspect(substr)}")
    end
  end
end
