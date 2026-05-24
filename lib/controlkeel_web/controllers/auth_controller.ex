defmodule ControlKeelWeb.AuthController do
  @moduledoc "Browser auth session helpers."

  use ControlKeelWeb, :controller

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> delete_session(:current_org_id)
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_org_id)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/")
  end
end
