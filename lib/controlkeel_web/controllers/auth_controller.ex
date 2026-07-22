defmodule ControlKeelWeb.AuthController do
  @moduledoc """
  Browser auth session helpers.

  ## Signed completion tokens

  LiveViews cannot call `put_session/3` directly because the session lives
  on the parent HTTP conn, not the live socket. The invitation acceptance
  flow needs to establish a session after the LiveView finishes:

    * **Invitation acceptance** — `InvitationLive` accepts the invite, then
      redirects to `/auth/complete/:token` with a signed Phoenix.Token
      carrying `%{user_id, org_id}`. The invite token itself is single-use
      and already consumed by accept; the completion token is a separate
      short-lived signed payload.

  The signed token has a 60-second max-age so a stale completion link
  cannot be replayed.

  Browser OAuth sign-in (Google + GitHub) does NOT use this path — it
  sets session keys directly inside `OAuthLoginController`.
  """

  use ControlKeelWeb, :controller

  @completion_salt "auth-completion"
  @completion_max_age 60

  def logout(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> delete_session(:current_org_id)
    |> delete_session(:oauth_state)
    |> delete_session(:oauth_provider)
    |> delete_session(:oauth_session_params)
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_org_id)
    |> delete_session(:saml_relay_state)
    |> delete_session(:saml_org_id)
    |> delete_session(:session_last_active)
    |> put_flash(:info, "Signed out")
    |> redirect(to: ~p"/auth/login")
  end

  @doc """
  Mint a signed completion token for the invitation flow. Called by
  `InvitationLive` after the invite is accepted.
  """
  @spec sign_completion_token(integer(), integer()) :: String.t()
  def sign_completion_token(user_id, org_id) when is_integer(user_id) and is_integer(org_id) do
    Phoenix.Token.sign(
      ControlKeelWeb.Endpoint,
      @completion_salt,
      %{user_id: user_id, org_id: org_id}
    )
  end

  @doc """
  Complete an invitation by setting session keys from a signed token.

  Routes:
    GET /auth/complete/:token
  """
  def complete(conn, %{"token" => token}) do
    case Phoenix.Token.verify(
           ControlKeelWeb.Endpoint,
           @completion_salt,
           token,
           max_age: @completion_max_age
         ) do
      {:ok, %{user_id: user_id, org_id: org_id}}
      when is_integer(user_id) and is_integer(org_id) ->
        conn
        |> put_session(:current_user_id, user_id)
        |> put_session(:current_org_id, org_id)
        |> put_session(:session_last_active, DateTime.utc_now() |> DateTime.to_iso8601())
        |> put_flash(:info, "Welcome to ControlKeel.")
        |> redirect(to: ~p"/cloud/projects")

      _ ->
        conn
        |> put_flash(:error, "Sign-in link expired. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end
end
