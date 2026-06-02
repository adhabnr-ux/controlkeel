defmodule ControlKeelWeb.Plugs.BrowserAuthPlugsTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeelWeb.Plugs.LoadCurrentUser

  setup %{conn: conn} do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})

    {:ok, user, membership} =
      Accounts.ensure_sso_membership(org.id, %{"email" => "user@example.com"}, role: "admin")

    conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})
    {:ok, conn: conn, org: org, user: user, membership: membership}
  end

  test "LoadCurrentUser assigns user and active membership", %{
    conn: conn,
    user: user,
    membership: membership
  } do
    conn = LoadCurrentUser.call(conn, [])
    assert conn.assigns.current_user.id == user.id
    assert conn.assigns.current_membership.id == membership.id
  end
end
