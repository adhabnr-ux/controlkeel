defmodule ControlKeel.OidcTestAdapter do
  @behaviour ControlKeel.Accounts.OidcClient

  @impl true
  def exchange_and_verify(_idp, code, _redirect_uri, _opts) do
    case Process.get({__MODULE__, code}) do
      nil -> {:error, {:token_exchange_failed, :not_stubbed}}
      {:error, reason} -> {:error, reason}
      claims when is_map(claims) -> {:ok, claims}
    end
  end

  def put(code, result), do: Process.put({__MODULE__, code}, result)
end
