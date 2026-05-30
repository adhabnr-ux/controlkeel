defmodule ControlKeelWeb.Plugs.RequireOrgRole do
  @moduledoc "Requires a signed-in active org member with a minimum role."

  import Plug.Conn
  import Phoenix.Controller

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership

  def init(opts), do: opts

  def call(conn, opts) do
    required = Keyword.get(opts, :role, "viewer")

    case conn.assigns[:current_membership] do
      %Membership{status: "active", role: role} when is_binary(role) ->
        if Accounts.role_at_least?(role, required) do
          conn
        else
          forbidden(conn)
        end

      _ ->
        forbidden(conn)
    end
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> put_resp_content_type("text/plain")
    |> text("Forbidden")
    |> halt()
  end
end
