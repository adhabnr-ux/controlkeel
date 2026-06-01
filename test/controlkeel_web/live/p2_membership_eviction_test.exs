defmodule ControlKeelWeb.P2MembershipEvictionTest do
  @moduledoc """
  P2 slice: when an admin revokes or demotes a user's membership, any
  LiveView the user has open should be evicted to /auth/login within one
  PubSub roundtrip.
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)

    {:ok, org} =
      Accounts.create_org(%{name: "Evict", slug: "evict-#{System.unique_integer([:positive])}"})

    # A separate owner so revoke/demote of the test user doesn't trip last-owner protection
    {:ok, owner} =
      Accounts.create_user(%{email: "owner-#{System.unique_integer([:positive])}@x.test"})

    {:ok, _} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: owner.id,
        org_id: org.id,
        role: "owner",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    {:ok, victim} =
      Accounts.create_user(%{email: "victim-#{System.unique_integer([:positive])}@x.test"})

    {:ok, victim_membership} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: victim.id,
        org_id: org.id,
        role: "admin",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    {:ok, org: org, victim: victim, victim_membership: victim_membership}
  end

  defp sign_in(conn, user, org) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:current_user_id, user.id)
    |> put_session(:current_org_id, org.id)
  end

  test "revoking a connected user's membership evicts the LiveView to /auth/login",
       %{conn: conn, org: org, victim: victim, victim_membership: m} do
    conn = sign_in(conn, victim, org)
    {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/members")

    # Sanity: LiveView is alive
    assert render(lv) =~ "Members"

    # Trigger revocation. Broadcast happens inside Accounts.revoke_membership.
    {:ok, _} = Accounts.revoke_membership(m.id)

    # The LiveView should receive {:membership_changed, ...} and push_navigate to /auth/login
    assert_redirect(lv, "/auth/login", 1000)
  end

  test "demoting a user's role evicts the LiveView",
       %{conn: conn, org: org, victim: victim, victim_membership: m} do
    conn = sign_in(conn, victim, org)
    {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/members")

    {:ok, _} = Accounts.update_membership_role(m.id, "member")

    assert_redirect(lv, "/auth/login", 1000)
  end

  test "broadcast does not affect a different user's LiveView",
       %{conn: conn, org: org, victim: _victim, victim_membership: m} do
    # Sign in as a different admin and open a LiveView
    {:ok, bystander} =
      Accounts.create_user(%{email: "bystander-#{System.unique_integer([:positive])}@x.test"})

    {:ok, _} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: bystander.id,
        org_id: org.id,
        role: "admin",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    conn = sign_in(conn, bystander, org)
    {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/members")

    # Revoke the OTHER membership — bystander should not be redirected
    {:ok, _} = Accounts.revoke_membership(m.id)

    # Give PubSub a beat to flush
    Process.sleep(100)

    assert Process.alive?(lv.pid),
           "bystander LiveView should still be alive after another user's revoke"

    assert render(lv) =~ "Members"
  end
end
