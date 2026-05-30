defmodule ControlKeel.SamlTestAdapter do
  @moduledoc """
  Test-only SAML adapter. Stubs `sso_url/1` and `verify_response/2` via the
  caller's process dictionary so tests can inject specific outcomes.
  """

  @behaviour ControlKeel.Accounts.SamlClient

  @impl true
  def sso_url(_idp) do
    case Process.get({__MODULE__, :sso_url}) do
      nil -> {:error, :sso_url_not_stubbed}
      {:error, _} = err -> err
      url when is_binary(url) -> {:ok, url}
    end
  end

  @impl true
  def verify_response(_idp, response_b64) do
    case Process.get({__MODULE__, {:response, response_b64}}) do
      nil -> {:error, {:verify_failed, :not_stubbed}}
      {:error, _} = err -> err
      claims when is_map(claims) -> {:ok, claims}
    end
  end

  @doc "Stub the SSO URL for the test process."
  def put_sso_url(url), do: Process.put({__MODULE__, :sso_url}, url)

  @doc "Stub the verify_response outcome for one particular response payload."
  def put_response(response_b64, result),
    do: Process.put({__MODULE__, {:response, response_b64}}, result)
end
