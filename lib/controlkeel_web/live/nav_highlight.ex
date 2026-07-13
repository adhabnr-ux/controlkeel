defmodule ControlKeelWeb.NavHighlight do
  @moduledoc """
  Sets the `@current_path` socket assign from the LiveView's request URI.

  Framework layouts read `@current_path` to highlight the active nav link (e.g.
  the observability subnav). Attached as an `on_mount` hook on the live_sessions
  whose layout needs it, so individual LiveViews don't have to set it manually.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(_arg, _params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, nil)
      |> attach_hook(:__current_path__, :handle_params, fn _params, uri, socket ->
        {:cont, assign(socket, :current_path, URI.parse(uri).path)}
      end)

    {:cont, socket}
  end
end
