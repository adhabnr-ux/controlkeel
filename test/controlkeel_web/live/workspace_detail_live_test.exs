defmodule ControlKeelWeb.WorkspaceDetailLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Mission

  defp create_user!(email) do
    {:ok, user} = Accounts.create_user(%{email: email})
    user
  end

  defp create_workspace(attrs) do
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()
      |> Map.merge(%{
        "agent" => "claude",
        "industry" => "web",
        "compliance_profile" => "general",
        "status" => "active"
      })

    {:ok, ws} = Mission.create_workspace(attrs)
    ws
  end

  defp create_session!(workspace_id, attrs) do
    {:ok, session} =
      Mission.create_session(
        %{
          title: "Investigate payments",
          objective: "Trace the payments failure",
          risk_tier: "high",
          status: "active",
          budget_cents: 10_000,
          spent_cents: 2500,
          workspace_id: workspace_id
        }
        |> Map.merge(attrs)
      )

    session
  end

  describe "local mode" do
    test "renders workspace default information and its sessions" do
      {:ok, org} = Accounts.create_org(%{name: "Wslocal", slug: "wslocal"})
      ws = create_workspace(%{name: "Core", slug: "core", industry: "web", org_id: org.id})

      s1 = create_session!(ws.id, %{title: "First session"})
      s2 = create_session!(ws.id, %{title: "Second session"})

      {:ok, _view, html} = live(build_conn(), ~p"/organizations/#{org.slug}/workspaces/#{ws.id}")

      assert html =~ "Core"
      assert html =~ "core"
      # Header stat row mirrors the org home layout.
      assert html =~ "Slug"
      assert html =~ "Sessions"
      assert html =~ "Monthly budget"
      # Session rows render in the missions-style table.
      assert html =~ "First session"
      assert html =~ "Second session"
      assert html =~ "$100"
    end

    test "shows an empty state when the workspace has no sessions" do
      {:ok, org} = Accounts.create_org(%{name: "Empty Org", slug: "empty-org"})
      ws = create_workspace(%{name: "Empty", slug: "empty", industry: "web", org_id: org.id})

      {:ok, _view, html} = live(build_conn(), ~p"/organizations/empty-org/workspaces/#{ws.id}")

      assert html =~ "No sessions yet."
    end

    test "redirects for an unknown workspace id" do
      {:ok, _org} = Accounts.create_org(%{name: "None", slug: "none"})

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(build_conn(), ~p"/organizations/none/workspaces/999999")

      assert msg =~ "Workspace not found."
    end

    test "redirects for a non-numeric id" do
      {:ok, _org} = Accounts.create_org(%{name: "None", slug: "none"})

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(build_conn(), ~p"/organizations/none/workspaces/not-a-number")

      assert msg =~ "Invalid workspace id."
    end

    test "redirects when the workspace belongs to a different org slug" do
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})

      ws =
        create_workspace(%{name: "Belongs To A", slug: "a-ws", industry: "web", org_id: org_a.id})

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(build_conn(), ~p"/organizations/org-b/workspaces/#{ws.id}")

      assert msg =~ "does not belong to this organization"
    end
  end

  describe "cloud mode org scoping" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    test "a member of the workspace's org can view it" do
      owner = create_user!("ws-owner@example.com")
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Scopeco", slug: "scopeco"})
      ws = create_workspace(%{name: "Scoped", slug: "scoped", industry: "web", org_id: org.id})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_user_id" => owner.id,
          "current_org_id" => org.id
        })

      {:ok, _view, html} = live(conn, ~p"/organizations/scopeco/workspaces/#{ws.id}")

      assert html =~ "Scoped"
      assert html =~ "Scoped"
    end

    test "a user outside the org is refused access" do
      owner_a = create_user!("scope-a@example.com")
      {:ok, org_a} = Accounts.create_org_with_owner(owner_a.id, %{name: "A", slug: "a"})

      ws_a =
        create_workspace(%{name: "Secret WS", slug: "secret", industry: "web", org_id: org_a.id})

      outsider = create_user!("scope-b@example.com")
      {:ok, org_b} = Accounts.create_org_with_owner(outsider.id, %{name: "B", slug: "b"})

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_user_id" => outsider.id,
          "current_org_id" => org_b.id
        })

      assert {:error, {:live_redirect, %{to: "/organizations", flash: %{"error" => msg}}}} =
               live(conn, ~p"/organizations/a/workspaces/#{ws_a.id}")

      assert msg =~ "Workspace belongs to a different organization."
    end
  end
end
