defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  # Public marketing pages render inside the :public framework layout
  # (ControlKeelWeb.Layouts). The layout reads @current_user/@flash directly,
  # so nothing needs to be forwarded from the templates.
  plug :put_layout, html: {ControlKeelWeb.Layouts, :public}

  alias ControlKeel.Skills

  def home(conn, _params) do
    render(conn, :home)
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started,
      install_channels: Skills.install_channels(),
      agent_integrations: Skills.agent_integrations()
    )
  end
end
