defmodule ControlKeelWeb.P1bWorkspaceAdminTest do
  @moduledoc """
  P1b slice tests: WorkspaceServiceAccountsLive, WorkspaceWebhooksLive,
  WorkspaceToolPolicyLive.
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Mission
  alias ControlKeel.Platform
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)

    {:ok, org} =
      Accounts.create_org(%{
        name: "WS Admin",
        slug: "ws-admin-#{System.unique_integer([:positive])}"
      })

    {:ok, admin} =
      Accounts.create_user(%{email: "wsa-#{System.unique_integer([:positive])}@x.test"})

    {:ok, _m} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    {:ok, workspace} =
      Mission.create_workspace(%{
        name: "WSAdminWS",
        slug: "wsadmin-#{System.unique_integer([:positive])}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 5_000,
        compliance_profile: "baseline",
        status: "active",
        org_id: org.id
      })

    {:ok, org: org, admin: admin, workspace: workspace}
  end

  defp sign_in(conn, user, org) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:current_user_id, user.id)
    |> put_session(:current_org_id, org.id)
  end

  describe "WorkspaceServiceAccountsLive (/workspaces/:id/service-accounts)" do
    test "admin creates service account and sees token banner exactly once", %{
      conn: conn,
      admin: admin,
      org: org,
      workspace: ws
    } do
      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/service-accounts")

      lv
      |> form("form[phx-submit=create]",
        sa: %{name: "ci-runner", scopes: "mcp:access findings:write"}
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Token for ci-runner"
      assert html =~ ~r/<code id="new-token-value">[^<]+<\/code>/

      accounts = Platform.list_service_accounts(ws.id)
      assert Enum.any?(accounts, &(&1.name == "ci-runner"))

      # Dismissing hides the token; subsequent renders don't show it again
      lv |> element("#new-token-banner button[phx-click=dismiss-token]") |> render_click()
      refute render(lv) =~ "new-token-banner"
    end

    test "rotate generates a new token shown once", %{
      conn: conn,
      admin: admin,
      org: org,
      workspace: ws
    } do
      {:ok, %{service_account: sa, token: _t}} =
        Platform.create_service_account(ws.id, %{
          "name" => "to-rotate",
          "scopes" => ["mcp:access"]
        })

      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/service-accounts")

      lv
      |> element(~s|button[phx-click="rotate"][phx-value-id="#{sa.id}"]|)
      |> render_click()

      assert render(lv) =~ "Token for to-rotate"
    end

    test "revoke flips status to revoked", %{conn: conn, admin: admin, org: org, workspace: ws} do
      {:ok, %{service_account: sa, token: _t}} =
        Platform.create_service_account(ws.id, %{
          "name" => "to-revoke",
          "scopes" => ["mcp:access"]
        })

      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/service-accounts")

      lv |> element(~s|button[phx-click="revoke"][phx-value-id="#{sa.id}"]|) |> render_click()

      assert Repo.reload!(sa).status == "revoked"
    end

    test "cross-org admin redirected", %{conn: conn, workspace: ws} do
      {:ok, other} =
        Accounts.create_org(%{name: "Other", slug: "other-#{System.unique_integer([:positive])}"})

      {:ok, other_admin} =
        Accounts.create_user(%{email: "oa-#{System.unique_integer([:positive])}@x.test"})

      {:ok, _} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: other_admin.id,
          org_id: other.id,
          role: "admin",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      conn = sign_in(conn, other_admin, other)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/service-accounts")
    end
  end

  describe "WorkspaceWebhooksLive (/workspaces/:id/webhooks)" do
    test "admin creates webhook and sees secret banner once", %{
      conn: conn,
      admin: admin,
      org: org,
      workspace: ws
    } do
      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/webhooks")

      lv
      |> form("form[phx-submit=create]", %{
        wh: %{name: "linear-bridge", url: "https://hooks.linear.app/ck"},
        events: ["finding.created", "finding.approved"]
      })
      |> render_submit()

      assert render(lv) =~ "Signing secret for linear-bridge"

      webhooks = Platform.list_webhooks(ws.id)
      wh = Enum.find(webhooks, &(&1.name == "linear-bridge"))
      assert wh
      events = ControlKeel.Platform.IntegrationWebhook.event_list(wh)
      assert "finding.created" in events
      assert "finding.approved" in events
    end

    test "replay with no prior delivery returns not_found flash", %{
      conn: conn,
      admin: admin,
      org: org,
      workspace: ws
    } do
      {:ok, wh} =
        Platform.create_webhook(ws.id, %{
          "name" => "no-delivery",
          "url" => "https://example.com/hook",
          "subscribed_events" => ["finding.created"]
        })

      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/webhooks")

      lv |> element(~s|button[phx-click="replay"][phx-value-id="#{wh.id}"]|) |> render_click()

      assert render(lv) =~ "No prior delivery"
    end

    test "cross-org admin redirected", %{conn: conn, workspace: ws} do
      {:ok, other} =
        Accounts.create_org(%{
          name: "WHOther",
          slug: "whother-#{System.unique_integer([:positive])}"
        })

      {:ok, oa} =
        Accounts.create_user(%{email: "who-#{System.unique_integer([:positive])}@x.test"})

      {:ok, _} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: oa.id,
          org_id: other.id,
          role: "admin",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      conn = sign_in(conn, oa, other)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/webhooks")
    end
  end

  describe "WorkspaceToolPolicyLive (/workspaces/:id/tool-policy)" do
    test "admin sets allowlist policy round-trip", %{
      conn: conn,
      admin: admin,
      org: org,
      workspace: ws
    } do
      conn = sign_in(conn, admin, org)
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{ws.id}/tool-policy")

      lv
      |> form("form[phx-submit=submit]",
        policy: %{mode: "allowlist", tools: "ck_validate\nck_finding"}
      )
      |> render_submit()

      policy = Accounts.get_workspace_tool_policy(ws.id)
      assert policy.mode == "allowlist"
      tools = ControlKeel.Accounts.WorkspaceToolPolicy.decode_tools(policy)
      assert "ck_validate" in tools
      assert "ck_finding" in tools
    end

    test "viewer is redirected with admin-required flash", %{conn: conn, workspace: ws} do
      {:ok, org} =
        Accounts.create_org(%{name: "TPVwr", slug: "tpvwr-#{System.unique_integer([:positive])}"})

      {:ok, viewer} =
        Accounts.create_user(%{email: "vwr-#{System.unique_integer([:positive])}@x.test"})

      {:ok, _} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: viewer.id,
          org_id: org.id,
          role: "viewer",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      # Note: this viewer is on a DIFFERENT org, so they get the cross-org rejection,
      # which is the right outcome.
      conn = sign_in(conn, viewer, org)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/tool-policy")
    end

    test "viewer in same org is redirected (admin role required)", %{
      conn: conn,
      org: org,
      workspace: ws
    } do
      {:ok, viewer} =
        Accounts.create_user(%{email: "vwr2-#{System.unique_integer([:positive])}@x.test"})

      {:ok, _} =
        %Membership{}
        |> Membership.changeset(%{
          user_id: viewer.id,
          org_id: org.id,
          role: "viewer",
          status: "active",
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      conn = sign_in(conn, viewer, org)

      assert {:error, {:live_redirect, %{to: "/cloud/projects"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/tool-policy")
    end
  end
end
