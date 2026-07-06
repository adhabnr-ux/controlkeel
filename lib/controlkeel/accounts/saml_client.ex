defmodule ControlKeel.Accounts.SamlClient do
  @moduledoc """
  SAML response verification boundary.

  Mirrors `ControlKeel.Accounts.OidcClient`: controllers delegate to a
  pluggable adapter rather than trusting POST parameters. The default adapter
  refuses to verify on its own because real SAML response verification requires
  an XML-signature library (e.g. `:samly`, `:esaml`) — those are deployment
  choices, not library choices baked into ControlKeel.

  To wire SAML in production, point the config at an adapter that knows how to:

      1. Parse the IdP's metadata (from `idp["idp_metadata_url"]`) to discover the
         SSO endpoint and signing certificate.
      2. Validate the SAML response signature against the cert.
      3. Validate audience, recipient, timestamps, and NameID/email claims.

      config :controlkeel, :saml_client_adapter, MyApp.SamlAdapter

  Adapter return shape:

    - `sso_url/1`         → `{:ok, "https://idp/sso"} | {:error, reason}`
    - `verify_response/2` → `{:ok, %{"email" => "...", "name" => "..."}} | {:error, reason}`

  The returned claims map is passed directly to
  `ControlKeel.Accounts.ensure_sso_membership/3`, so it should at minimum
  contain `"email"`.
  """

  @callback sso_url(idp :: map()) :: {:ok, String.t()} | {:error, atom() | term()}
  @callback verify_response(idp :: map(), saml_response_b64 :: String.t()) ::
              {:ok, map()} | {:error, atom() | term()}

  @doc "Resolve the IdP's SSO endpoint URL for the redirect-binding start flow."
  @spec sso_url(map()) :: {:ok, String.t()} | {:error, term()}
  def sso_url(idp) when is_map(idp), do: adapter().sso_url(idp)

  @doc "Verify a base64-encoded SAML response and return verified claims."
  @spec verify_response(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def verify_response(idp, response_b64)
      when is_map(idp) and is_binary(response_b64) and response_b64 != "" do
    adapter().verify_response(idp, response_b64)
  end

  def verify_response(_, _), do: {:error, :missing_saml_response}

  defp adapter do
    Application.get_env(:controlkeel, :saml_client_adapter, __MODULE__.DefaultAdapter)
  end
end
