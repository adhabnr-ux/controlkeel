defmodule ControlKeelWeb.OrganizationsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  describe "local mode /organizations" do
    test "index lists every active org" do
      {:ok, _} = Accounts.create_org(%{name: "Alpha", slug: "alpha"})
      {:ok, _} = Accounts.create_org(%{name: "Beta", slug: "beta"})
      {:ok, _} = Accounts.create_org(%{name: "Gamma", slug: "gamma", status: "disabled"})

      {:ok, _view, html} = live(build_conn(), ~p"/organizations")

      assert html =~ "Your organizations"
      assert html =~ "Alpha"
      assert html =~ "Beta"
      refute html =~ "Gamma"
    end

    test "index renders empty state when there are no orgs" do
      {:ok, _view, html} = live(build_conn(), ~p"/organizations")

      assert html =~ "No organizations yet."
    end

    test "local mode renders Role column header but every row's role is nil (no badge)" do
      {:ok, _} = Accounts.create_org(%{name: "Local Co", slug: "local-co"})

      {:ok, view, html} = live(build_conn(), ~p"/organizations")

      # Header is present.
      assert html =~ ">Role<"

      # Row is present, but no role badge is rendered — only the muted em-dash placeholder.
      assert render(view) =~ "Local Co"
      refute render(view) =~ ~s(owner)
      refute render(view) =~ ~s(admin)
      refute render(view) =~ ~s(member)
      refute render(view) =~ ~s(viewer)
      # The placeholder dash is rendered for null roles.
      assert render(view) =~ "—"
    end

    test "new_org click opens the create modal" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")

      refute render(view) =~ "New organization"
      refute render(view) =~ ~s(id="organization-form")

      render_click(view, "new_org")

      html = render(view)
      assert html =~ "New organization"
      assert html =~ ~s(id="organization-form")
    end

    test "cancel_new click closes the create modal" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")

      render_click(view, "new_org")
      assert render(view) =~ ~s(id="organization-form")

      render_click(view, "cancel_new")
      refute render(view) =~ ~s(id="organization-form")
    end

    test "save inserts an org with no membership" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")
      render_click(view, "new_org")

      view
      |> form("#organization-form", org: %{name: "New Co", slug: "new-co"})
      |> render_submit()

      org = Repo.get_by!(ControlKeel.Accounts.Org, slug: "new-co")
      assert org.name == "New Co"
      assert org.status == "active"

      # Local mode never creates a membership.
      assert Repo.aggregate(Membership, :count) == 0
    end

    test "save closes the modal and refreshes the list" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")
      render_click(view, "new_org")

      view
      |> form("#organization-form", org: %{name: "Modal Co", slug: "modal-co"})
      |> render_submit()

      html = render(view)
      refute html =~ ~s(id="organization-form")
      assert html =~ "Modal Co"
    end

    test "save re-renders the form inside the modal on validation errors" do
      {:ok, view, _html} = live(build_conn(), ~p"/organizations")
      render_click(view, "new_org")

      html =
        view
        |> form("#organization-form", org: %{name: "", slug: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert html =~ ~s(id="organization-form")
    end
  end

  describe "cloud mode /organizations" do
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

      {:ok, user} = Accounts.create_user(%{email: "cloud@example.com", name: "Cloud"})
      conn = build_conn() |> Plug.Test.init_test_session(%{"current_user_id" => user.id})

      {:ok, conn: conn, user: user}
    end

    test "index shows only the signed-in user's orgs", %{conn: conn, user: user} do
      {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Mine", slug: "mine"})

      {:ok, other} = Accounts.create_user(%{email: "other@example.com"})
      {:ok, _} = Accounts.create_org_with_owner(other.id, %{name: "Theirs", slug: "theirs"})

      {:ok, _view, html} = live(conn, ~p"/organizations")

      assert html =~ "Mine"
      refute html =~ "Theirs"
      assert html =~ ~p"/organizations/#{org.slug}"
    end

    test "cloud mode renders the user's role per org row", %{conn: conn, user: user} do
      {:ok, _} = Accounts.create_org_with_owner(user.id, %{name: "Owned", slug: "owned"})

      {:ok, _view, html} = live(conn, ~p"/organizations")

      # Header is present, and the owner role badge is rendered (not the muted placeholder).
      assert html =~ ">Role<"
      assert html =~ "Owned"
      assert html =~ "owner"
      refute html =~ "—"
    end

    test "save inserts an org plus an owner membership for the current user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/organizations")
      render_click(view, "new_org")

      view
      |> form("#organization-form", org: %{name: "Cloud Co", slug: "cloud-co"})
      |> render_submit()

      org = Repo.get_by!(ControlKeel.Accounts.Org, slug: "cloud-co")

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership != nil
      assert membership.role == "owner"
    end

    test "index redirects to login when there is no signed-in user" do
      conn = build_conn() |> Plug.Test.init_test_session(%{})

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/organizations")
      assert to == "/auth/login"
    end
  end
end
