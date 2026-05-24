defmodule ControlKeelWeb.Plugs.LoadCurrentUser do
  @moduledoc "Loads the SSO user and org membership from the browser session."

  import Plug.Conn

  alias ControlKeel.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :current_user_id)
    org_id = get_session(conn, :current_org_id)

    user = if is_integer(user_id), do: Accounts.get_user(user_id)

    membership =
      if user && is_integer(org_id), do: Accounts.get_active_membership(user.id, org_id)

    conn
    |> assign(:current_user, user)
    |> assign(:current_org_id, org_id)
    |> assign(:current_membership, membership)
  end
end
