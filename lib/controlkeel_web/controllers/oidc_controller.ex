defmodule ControlKeelWeb.OidcController do
  @moduledoc """
  Minimal OIDC redirect/callback scaffold for Phase 6 SSO.

  This slice only wires public IdP metadata into a browser login round-trip and
  JIT provisioning. It deliberately does not store client secrets or perform a
  production token exchange/JWT verification. In tests and local scaffolding,
  verified claims are supplied on the callback request; the token-exchange
  boundary will be replaced by full OIDC verification in a follow-on slice.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.OidcClient

  def start(conn, %{"org" => slug}) do
    with {:ok, org} <- fetch_org(slug),
         {:ok, idp} <- oidc_config(org),
         {:ok, authorize_url, state} <- authorize_url(conn, org, idp) do
      conn
      |> put_session(:oidc_state, state)
      |> put_session(:oidc_org_id, org.id)
      |> redirect(external: authorize_url)
    else
      {:error, :org_not_found} ->
        text_error(conn, :not_found, "Org not found")

      {:error, :oidc_not_configured} ->
        text_error(conn, :bad_request, "OIDC is not configured for this org")
    end
  end

  def start(conn, _params), do: text_error(conn, :bad_request, "Missing org")

  def callback(conn, params) do
    with :ok <- verify_state(conn, Map.get(params, "state")),
         {:ok, org} <- callback_org(conn),
         {:ok, idp} <- oidc_config(org),
         {:ok, code} <- fetch_code(params),
         {:ok, claims} <-
           OidcClient.exchange_and_verify(
             idp_with_org(idp, org),
             code,
             url(~p"/auth/oidc/callback")
           ),
         {:ok, user, _membership} <- Accounts.ensure_sso_membership(org.id, claims) do
      conn
      |> delete_session(:oidc_state)
      |> delete_session(:oidc_org_id)
      |> put_session(:current_user_id, user.id)
      |> put_session(:current_org_id, org.id)
      |> put_flash(:info, "Signed in with SSO")
      |> redirect(to: ~p"/cloud/projects")
    else
      {:error, :invalid_state} ->
        text_error(conn, :forbidden, "Invalid OIDC state")

      {:error, :missing_code} ->
        text_error(conn, :bad_request, "Missing OIDC code")

      {:error, :missing_email} ->
        text_error(conn, :bad_request, "OIDC claims missing email")

      {:error, :issuer_mismatch} ->
        text_error(conn, :forbidden, "OIDC issuer mismatch")

      {:error, :audience_mismatch} ->
        text_error(conn, :forbidden, "OIDC audience mismatch")

      {:error, :token_expired} ->
        text_error(conn, :forbidden, "OIDC token expired")

      {:error, :jwt_signature_verification_unavailable} ->
        text_error(conn, :forbidden, "OIDC JWT verification unavailable")

      {:error, {:token_exchange_failed, _}} ->
        text_error(conn, :bad_gateway, "OIDC token exchange failed")

      {:error, :org_not_found} ->
        text_error(conn, :not_found, "Org not found")

      {:error, :oidc_not_configured} ->
        text_error(conn, :bad_request, "OIDC is not configured for this org")

      {:error, changeset} ->
        text_error(conn, :bad_request, inspect(changeset))
    end
  end

  defp fetch_org(slug) when is_binary(slug) do
    case Accounts.get_org_by_slug(slug) do
      nil -> {:error, :org_not_found}
      org -> {:ok, org}
    end
  end

  defp fetch_org(_), do: {:error, :org_not_found}

  defp oidc_config(org) do
    case Accounts.get_org_identity_provider(org) do
      %{"type" => "oidc", "issuer" => issuer, "client_id" => client_id} = idp
      when is_binary(issuer) and is_binary(client_id) ->
        {:ok, idp}

      _ ->
        {:error, :oidc_not_configured}
    end
  end

  defp authorize_url(_conn, org, idp) do
    state = generate_state()
    redirect_uri = url(~p"/auth/oidc/callback")

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => idp["client_id"],
        "redirect_uri" => redirect_uri,
        "scope" => Map.get(idp, "scope", "openid email profile"),
        "state" => state,
        "login_hint" => org.slug
      })

    {:ok, String.trim_trailing(idp["issuer"], "/") <> "/authorize?" <> query, state}
  end

  defp verify_state(conn, state) when is_binary(state) and state != "" do
    if get_session(conn, :oidc_state) == state, do: :ok, else: {:error, :invalid_state}
  end

  defp verify_state(_conn, _state), do: {:error, :invalid_state}

  defp callback_org(conn) do
    case get_session(conn, :oidc_org_id) do
      id when is_integer(id) ->
        case Accounts.get_org(id) do
          nil -> {:error, :org_not_found}
          org -> {:ok, org}
        end

      _ ->
        {:error, :invalid_state}
    end
  end

  defp idp_with_org(idp, org), do: Map.put(idp, "org_slug", org.slug)

  defp fetch_code(%{"code" => code}) when is_binary(code) and code != "", do: {:ok, code}
  defp fetch_code(_), do: {:error, :missing_code}

  defp generate_state do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp text_error(conn, status, message) do
    conn
    |> put_status(status)
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
