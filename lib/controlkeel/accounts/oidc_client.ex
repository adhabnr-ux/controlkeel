defmodule ControlKeel.Accounts.OidcClient do
  @moduledoc """
  OIDC token exchange and verification boundary.

  Controllers call this module instead of trusting callback request parameters as
  identity claims. In production the default adapter performs provider discovery
  and token exchange with `Req`, verifies RS256 ID-token signatures against
  provider JWKS, then validates issuer/audience/expiration/email claims. Tests
  and controlled deployments can inject an adapter with
  `config :controlkeel, :oidc_client_adapter, MyAdapter`.

  Client secrets are not stored in org settings. If needed, the default adapter
  reads them from runtime env using `CONTROLKEEL_OIDC_CLIENT_SECRET_<ORG_SLUG>`.
  """

  @callback exchange_and_verify(map(), String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, atom() | term()}

  def exchange_and_verify(idp, code, redirect_uri, opts \\ []) do
    adapter().exchange_and_verify(idp, code, redirect_uri, opts)
  end

  defp adapter do
    Application.get_env(:controlkeel, :oidc_client_adapter, __MODULE__.DefaultAdapter)
  end
end
