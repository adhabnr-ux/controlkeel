defmodule ControlKeelWeb.SamlController do
  @moduledoc """
  SAML redirect-binding start + Assertion Consumer Service callback.

  Mirrors `ControlKeelWeb.OidcController` for SAML. Real SAML response
  verification is delegated to `ControlKeel.Accounts.SamlClient`'s configured
  adapter — see that module for production wiring.

  Both endpoints route through the browser pipeline (CSRF-protected and
  session-backed). The ACS endpoint accepts POST since SAML IdPs always POST
  the assertion back. CSRF must be skipped for that one specific route; the
  router wires it through a dedicated pipeline for that reason.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.SamlClient

  def start(conn, %{"org" => slug}) do
    with {:ok, org} <- fetch_org(slug),
         {:ok, idp} <- saml_config(org),
         {:ok, sso_url} <- SamlClient.sso_url(idp) do
      relay_state = generate_relay_state()
      redirect_url = append_relay_state(sso_url, relay_state)

      conn
      |> put_session(:saml_relay_state, relay_state)
      |> put_session(:saml_org_id, org.id)
      |> redirect(external: redirect_url)
    else
      {:error, :org_not_found} ->
        text_error(conn, :not_found, "Org not found")

      {:error, :saml_not_configured} ->
        text_error(conn, :bad_request, "SAML is not configured for this org")

      {:error, :saml_adapter_not_configured} ->
        text_error(conn, :service_unavailable, "SAML adapter is not configured")

      {:error, reason} ->
        text_error(conn, :bad_request, "SAML start failed: #{inspect(reason)}")
    end
  end

  def start(conn, _params), do: text_error(conn, :bad_request, "Missing org")

  def acs(conn, params) do
    with :ok <- verify_relay_state(conn, Map.get(params, "RelayState")),
         {:ok, org} <- callback_org(conn),
         {:ok, idp} <- saml_config(org),
         {:ok, response_b64} <- fetch_saml_response(params),
         {:ok, claims} <- SamlClient.verify_response(idp, response_b64),
         {:ok, user, _membership} <- Accounts.ensure_sso_membership(org.id, claims) do
      conn
      |> delete_session(:saml_relay_state)
      |> delete_session(:saml_org_id)
      |> put_session(:current_user_id, user.id)
      |> put_session(:current_org_id, org.id)
      |> put_flash(:info, "Signed in with SAML")
      |> redirect(to: ~p"/cloud/telemetry")
    else
      {:error, :invalid_relay_state} ->
        text_error(conn, :forbidden, "Invalid SAML RelayState")

      {:error, :missing_saml_response} ->
        text_error(conn, :bad_request, "Missing SAMLResponse")

      {:error, :missing_email} ->
        text_error(conn, :bad_request, "SAML assertion missing email")

      {:error, :org_not_found} ->
        text_error(conn, :not_found, "Org not found")

      {:error, :saml_not_configured} ->
        text_error(conn, :bad_request, "SAML is not configured for this org")

      {:error, :saml_adapter_not_configured} ->
        text_error(conn, :service_unavailable, "SAML adapter is not configured")

      {:error, :signature_invalid} ->
        text_error(conn, :forbidden, "SAML signature invalid")

      {:error, :assertion_expired} ->
        text_error(conn, :forbidden, "SAML assertion expired")

      {:error, :audience_mismatch} ->
        text_error(conn, :forbidden, "SAML audience mismatch")

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

  defp saml_config(org) do
    case Accounts.get_org_identity_provider(org) do
      %{"type" => "saml", "entity_id" => entity_id, "idp_metadata_url" => metadata_url} = idp
      when is_binary(entity_id) and is_binary(metadata_url) ->
        {:ok, idp}

      _ ->
        {:error, :saml_not_configured}
    end
  end

  defp callback_org(conn) do
    case get_session(conn, :saml_org_id) do
      id when is_integer(id) ->
        case Accounts.get_org(id) do
          nil -> {:error, :org_not_found}
          org -> {:ok, org}
        end

      _ ->
        {:error, :invalid_relay_state}
    end
  end

  defp verify_relay_state(conn, relay_state)
       when is_binary(relay_state) and relay_state != "" do
    if get_session(conn, :saml_relay_state) == relay_state,
      do: :ok,
      else: {:error, :invalid_relay_state}
  end

  defp verify_relay_state(_, _), do: {:error, :invalid_relay_state}

  defp fetch_saml_response(%{"SAMLResponse" => resp}) when is_binary(resp) and resp != "",
    do: {:ok, resp}

  defp fetch_saml_response(_), do: {:error, :missing_saml_response}

  defp generate_relay_state do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp append_relay_state(url, relay_state) do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    url <> separator <> "RelayState=" <> URI.encode_www_form(relay_state)
  end

  defp text_error(conn, status, message) do
    conn
    |> put_status(status)
    |> put_resp_content_type("text/plain")
    |> send_resp(status, message)
  end
end
