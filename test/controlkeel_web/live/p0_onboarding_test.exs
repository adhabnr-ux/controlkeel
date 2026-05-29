defmodule ControlKeelWeb.P0OnboardingTest do
  @moduledoc """
  P0 onboarding slice tests (docs/CLOUD_READINESS.md).
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Mission
  alias ControlKeel.Repo
  alias ControlKeelWeb.AuthController

  setup do
    # Force cloud mode for the surfaces that are cloud-only (signup, IdP page).
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)

    :ok
  end

  describe "P0.2 — SignupLive (/signup) in cloud mode" do
    test "submitting the form creates Org + User + active owner Membership and redirects to /auth/complete/:token", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/signup")

      slug = "acme-#{System.unique_integer([:positive])}"

      result =
        lv
        |> form("form", signup: %{
          email: "founder@acme.test",
          name: "Founder",
          org_name: "Acme",
          org_slug: slug
        })
        |> render_submit()

      # LiveView redirects to /auth/complete/<signed-token>.
      assert {:error, {:redirect, %{to: redirect_to}}} = result
      assert String.starts_with?(redirect_to, "/auth/complete/")

      user = Accounts.get_user_by_email("founder@acme.test")
      assert user
      assert user.name == "Founder"

      org = Accounts.get_org_by_slug(slug)
      assert org

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership
      assert membership.role == "owner"
    end

    test "duplicate email surfaces a friendly error and does not create org", %{conn: conn} do
      {:ok, _} = Accounts.create_user(%{email: "exists@acme.test"})

      {:ok, lv, _html} = live(conn, ~p"/signup")

      slug = "dup-#{System.unique_integer([:positive])}"

      html =
        lv
        |> form("form", signup: %{
          email: "exists@acme.test",
          name: "Dup",
          org_name: "Dup Org",
          org_slug: slug
        })
        |> render_submit()

      assert html =~ "already exists"
      assert Accounts.get_org_by_slug(slug) == nil
    end
  end

  describe "P0.5 — Invitation auto-login" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "Inviting Co", slug: "inviting-co-#{System.unique_integer([:positive])}"})
      {:ok, user} = Accounts.create_user(%{email: "invited@acme.test"})
      {:ok, _m, raw_token} = Accounts.invite_member(user.id, org.id)

      {:ok, org: org, user: user, raw_token: raw_token}
    end

    test "accept invitation redirects to /auth/complete/:token instead of dwelling on :accepted state", %{conn: conn, raw_token: token} do
      {:ok, lv, _html} = live(conn, ~p"/cloud/invitations/#{token}")

      result =
        lv
        |> form("#invitation-accept-form", %{"email" => "invited@acme.test"})
        |> render_submit()

      assert {:error, {:redirect, %{to: redirect_to}}} = result
      assert String.starts_with?(redirect_to, "/auth/complete/")
    end
  end

  describe "P0 — AuthController.complete sets session and redirects" do
    test "verifies signed token and lands on /cloud/projects", %{conn: conn} do
      {:ok, org} = Accounts.create_org(%{name: "Complete Co", slug: "complete-co-#{System.unique_integer([:positive])}"})
      {:ok, user} = Accounts.create_user(%{email: "complete@acme.test"})

      token = AuthController.sign_completion_token(user.id, org.id)

      conn = get(conn, ~p"/auth/complete/#{token}")

      assert redirected_to(conn) == "/cloud/projects"
      assert get_session(conn, :current_user_id) == user.id
      assert get_session(conn, :current_org_id) == org.id
    end

    test "expired/invalid token redirects to /auth/login", %{conn: conn} do
      conn = get(conn, ~p"/auth/complete/garbage")
      assert redirected_to(conn) == "/auth/login"
    end
  end

  describe "P0.4 — OrgSettingsAuthLive IdP config" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "IdP Co", slug: "idp-co-#{System.unique_integer([:positive])}"})
      {:ok, user} = Accounts.create_user(%{email: "idpadmin@acme.test"})

      {:ok, _m} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: user.id,
          org_id: org.id,
          role: "owner",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      {:ok, org: org, user: user}
    end

    test "submitting OIDC config round-trips through set_org_identity_provider", %{conn: conn, org: org, user: user} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_session(:current_user_id, user.id)
        |> put_session(:current_org_id, org.id)

      {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/settings/auth")

      _html =
        lv
        |> form("form", idp: %{
          type: "oidc",
          issuer: "https://accounts.google.com",
          client_id: "test-client-id-123",
          client_secret: "test-secret-xyz"
        })
        |> render_submit()

      idp = Accounts.get_org_identity_provider(org.id)
      assert idp["type"] == "oidc"
      assert idp["issuer"] == "https://accounts.google.com"
      assert idp["client_id"] == "test-client-id-123"
    end

    test "non-admin member is redirected away", %{conn: conn, org: org} do
      {:ok, user} = Accounts.create_user(%{email: "viewer@acme.test"})

      {:ok, _m} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: user.id,
          org_id: org.id,
          role: "viewer",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_session(:current_user_id, user.id)
        |> put_session(:current_org_id, org.id)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/org/#{org.slug}/settings/auth")
    end
  end

  describe "P0.6 — Mission.create_session idempotency" do
    setup do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Dedup",
          slug: "dedup-#{System.unique_integer([:positive])}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 5_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, workspace: workspace}
    end

    test "creating a session twice with the same external_id returns the existing record", %{workspace: ws} do
      # Let the schema auto-generate a ULID-formatted external_id on first call.
      {:ok, session_a} =
        Mission.create_session(%{
          title: "First",
          objective: "test",
          risk_tier: "low",
          budget_cents: 100,
          daily_budget_cents: 100,
          workspace_id: ws.id
        })

      # Refetch with its actual external_id and call create_session again with that same ID.
      session_a = Repo.reload!(session_a)
      assert session_a.external_id

      {:ok, session_b} =
        Mission.create_session(%{
          title: "Second (ignored)",
          objective: "test",
          risk_tier: "low",
          budget_cents: 100,
          daily_budget_cents: 100,
          workspace_id: ws.id,
          external_id: session_a.external_id
        })

      assert session_a.id == session_b.id
      assert session_b.title == "First"
    end

    test "different external_ids in same workspace create distinct sessions", %{workspace: ws} do
      {:ok, s1} =
        Mission.create_session(%{
          title: "A",
          objective: "o",
          risk_tier: "low",
          budget_cents: 1,
          daily_budget_cents: 1,
          workspace_id: ws.id
        })

      {:ok, s2} =
        Mission.create_session(%{
          title: "B",
          objective: "o",
          risk_tier: "low",
          budget_cents: 1,
          daily_budget_cents: 1,
          workspace_id: ws.id
        })

      assert s1.id != s2.id
      assert s1.external_id != s2.external_id
    end
  end
end
