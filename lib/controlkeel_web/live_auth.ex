defmodule ControlKeelWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hooks for cloud-mode authentication and org context loading.

  Two hooks:

    * `:require_cloud_auth` — in cloud/self_hosted mode requires an active org
      membership; redirects to `/auth/login` if none. In local mode this is a
      passthrough so local single-user deployments are unaffected.

    * `:load_if_available` — loads user/membership from session without gating.
      Use for pages that are public in local mode but show org-scoped data when
      a membership is present (e.g. home page).

  Both hooks assign:
    * `:current_user`       — `%Accounts.User{}` or `nil`
    * `:current_org_id`     — integer org id or `nil`
    * `:current_membership` — `%Accounts.Membership{}` or `nil`

  These override whatever the LoadCurrentUser plug may have already put in
  socket.assigns (they carry the same values from the same source).
  """

  import Phoenix.LiveView, only: [redirect: 2]
  import Phoenix.Component, only: [assign: 3]

  alias ControlKeel.{Accounts, RuntimeMode}

  @doc false
  def on_mount(:require_cloud_auth, _params, session, socket) do
    mode = RuntimeMode.current()

    if mode == :local do
      {:cont, load_auth(socket, session)}
    else
      socket = load_auth(socket, session)

      if socket.assigns[:current_membership] do
        {:cont, socket}
      else
        {:halt, redirect(socket, to: "/auth/login")}
      end
    end
  end

  @doc false
  def on_mount(:load_if_available, _params, session, socket) do
    {:cont, load_auth(socket, session)}
  end

  # --- Private ---

  defp load_auth(socket, session) do
    # Prefer values already put in socket.assigns by LoadCurrentUser plug
    # (set during initial HTTP request). Fall back to session map for WebSocket
    # reconnects and direct WS connections.
    case socket.assigns[:current_membership] do
      %Accounts.Membership{} ->
        socket

      _ ->
        user_id =
          socket.assigns[:current_user] && socket.assigns.current_user.id ||
            Map.get(session, "current_user_id") ||
            Map.get(session, :current_user_id)

        org_id =
          socket.assigns[:current_org_id] ||
            Map.get(session, "current_org_id") ||
            Map.get(session, :current_org_id)

        user = if is_integer(user_id), do: Accounts.get_user(user_id)

        membership =
          if user && is_integer(org_id),
            do: Accounts.get_active_membership(user.id, org_id)

        socket
        |> assign(:current_user, user)
        |> assign(:current_org_id, org_id)
        |> assign(:current_membership, membership)
    end
  end
end
