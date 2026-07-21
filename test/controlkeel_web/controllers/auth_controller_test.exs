defmodule ControlKeelWeb.AuthControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  setup do
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    :ok
  end

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
