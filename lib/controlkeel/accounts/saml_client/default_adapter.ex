defmodule ControlKeel.Accounts.SamlClient.DefaultAdapter do
  @moduledoc false
  @behaviour ControlKeel.Accounts.SamlClient

  @impl true
  def sso_url(_idp), do: {:error, :saml_adapter_not_configured}

  @impl true
  def verify_response(_idp, _response), do: {:error, :saml_adapter_not_configured}
end
