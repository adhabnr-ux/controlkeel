defmodule ControlKeelWeb.Plugs.RequireCloudAuth do
  @moduledoc """
  Controller plug counterpart to `ControlKeelWeb.LiveAuth.require_cloud_auth`.

  - In local mode: passthrough (single-user, no auth required).
  - In cloud/self_hosted mode: requires a signed-in user (`current_user`).
    Returns 401 JSON and halts if unauthenticated.

  Must run after `LoadCurrentUser` so `conn.assigns[:current_user]` is populated.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias ControlKeel.Runtime.Mode

  def init(opts), do: opts

  def call(conn, _opts) do
    if Mode.current() == :local do
      conn
    else
      current_user = conn.assigns[:current_user] || get_session(conn, :current_user_id)

      if current_user do
        conn
      else
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
      end
    end
  end
end
