defmodule ControlKeelWeb.Plugs.RequireCloudMode do
  @moduledoc """
  Redirects local-mode users away from auth routes.

  In local mode there is no OAuth/SSO — the single user has implicit access
  to all protected routes. Visiting `/auth/login` or `/auth/:provider/request`
  would be a dead end, so this plug redirects to `/dashboard`.

  Paths that are always allowed regardless of mode:
    * `/auth/logout` — session teardown
    * `/auth/complete/:token` — session-establishing completion links
    * `/auth/saml/*` — external IdP callbacks
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias ControlKeel.Runtime.Mode

  @auth_prefixes ["/auth/login", "/auth/google", "/auth/github"]
  @always_allowed ["/auth/logout", "/auth/complete", "/auth/saml"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if Mode.current() == :local and auth_path?(conn.request_path) do
      conn
      |> put_flash(:info, "Sign-in is not available in local mode.")
      |> redirect(to: "/dashboard")
      |> halt()
    else
      conn
    end
  end

  defp auth_path?(path) do
    Enum.any?(@auth_prefixes, &String.starts_with?(path, &1)) and
      not Enum.any?(@always_allowed, &String.starts_with?(path, &1))
  end
end
