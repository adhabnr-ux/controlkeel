defmodule ControlKeelWeb.P2bSessionTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.{Accounts, Repo}

  setup do
    previous_timeout = System.get_env("SESSION_IDLE_TIMEOUT_SECONDS")

    on_exit(fn ->
      if previous_timeout do
        System.put_env("SESSION_IDLE_TIMEOUT_SECONDS", previous_timeout)
      else
        System.delete_env("SESSION_IDLE_TIMEOUT_SECONDS")
      end
    end)

    :ok
  end

  # ── Accounts.sign_out_everywhere/1 ──────────────────────────────────

  describe "Accounts.sign_out_everywhere/1" do
    test "broadcasts on the signout topic for the target user" do
      user = insert_user()
      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.signout_topic(user.id))

      assert :ok == Accounts.sign_out_everywhere(user.id)
      assert_received :sign_out_everywhere
    end

    test "does not broadcast on a different user's topic" do
      user_a = insert_user()
      user_b = insert_user()

      Phoenix.PubSub.subscribe(ControlKeel.PubSub, Accounts.signout_topic(user_b.id))

      Accounts.sign_out_everywhere(user_a.id)
      refute_received :sign_out_everywhere
    end
  end

  describe "Accounts.signout_topic/1" do
    test "returns a user-scoped topic string" do
      assert Accounts.signout_topic(42) == "signout:user:42"
    end
  end

  # ── AuthController session_last_active ──────────────────────────────

  describe "AuthController.complete/2 stores session_last_active" do
    test "session_last_active is set after completion", %{conn: conn} do
      user = insert_user()
      org = insert_org()

      token = ControlKeelWeb.AuthController.sign_completion_token(user.id, org.id)

      conn = get(conn, ~p"/auth/complete/#{token}")

      last_active = Plug.Conn.get_session(conn, :session_last_active)
      assert last_active != nil

      # Should be a parseable ISO8601 timestamp
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(last_active)
    end
  end

  describe "AuthController.logout/1 clears session_last_active" do
    test "session_last_active is removed on logout", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{
          current_user_id: 1,
          current_org_id: 1,
          session_last_active: DateTime.utc_now() |> DateTime.to_iso8601()
        })
        |> get(~p"/auth/logout")

      assert Plug.Conn.get_session(conn, :session_last_active) == nil
      assert Plug.Conn.get_session(conn, :current_user_id) == nil
    end
  end

  describe "LoadCurrentUser sliding idle timeout" do
    test "clears stale sessions before loading assigns", %{conn: conn} do
      System.put_env("SESSION_IDLE_TIMEOUT_SECONDS", "1")
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "owner")
      stale = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          current_user_id: user.id,
          current_org_id: org.id,
          session_last_active: stale
        })
        |> ControlKeelWeb.Plugs.LoadCurrentUser.call([])

      assert conn.assigns.current_user == nil
      assert Plug.Conn.get_session(conn, :current_user_id) == nil
      assert Plug.Conn.get_session(conn, :session_last_active) == nil
    end

    test "refreshes session_last_active for active sessions", %{conn: conn} do
      System.put_env("SESSION_IDLE_TIMEOUT_SECONDS", "3600")
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "owner")
      prior = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601()

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          current_user_id: user.id,
          current_org_id: org.id,
          session_last_active: prior
        })
        |> ControlKeelWeb.Plugs.LoadCurrentUser.call([])

      refreshed = Plug.Conn.get_session(conn, :session_last_active)
      assert refreshed != prior
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(refreshed)
      assert conn.assigns.current_user.id == user.id
    end
  end

  # ── OrgSettingsGeneralLive sign-out-everywhere button ───────────────

  describe "OrgSettingsGeneralLive sign-out-everywhere button" do
    test "owner sees the sign-out-everywhere button", %{conn: conn} do
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "owner")

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "current_user_id" => user.id,
          "current_org_id" => org.id
        })

      {:ok, _view, html} = live(conn, ~p"/org/#{org.slug}/settings/general")
      assert html =~ "Sign out everywhere"
    end

    test "admin does not see the sign-out-everywhere button", %{conn: conn} do
      org = insert_org()
      user = insert_user()
      insert_active_membership(user.id, org.id, "admin")

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          "current_user_id" => user.id,
          "current_org_id" => org.id
        })

      {:ok, _view, html} = live(conn, ~p"/org/#{org.slug}/settings/general")
      refute html =~ "Sign out everywhere"
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

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
end
