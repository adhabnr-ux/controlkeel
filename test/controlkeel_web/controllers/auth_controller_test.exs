defmodule ControlKeelWeb.AuthControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  test "GET /auth/logout clears SSO session keys", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{
        current_user_id: 123,
        current_org_id: 456,
        oidc_state: "state",
        oidc_org_id: 456
      })
      |> get("/auth/logout")

    assert redirected_to(conn, 302) == "/auth/login"
    refute get_session(conn, :current_user_id)
    refute get_session(conn, :current_org_id)
    refute get_session(conn, :oidc_state)
    refute get_session(conn, :oidc_org_id)
  end
end
