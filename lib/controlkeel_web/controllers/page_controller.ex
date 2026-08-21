defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Skills

  # Public marketing pages render inside the `:public` framework layout
  # (ControlKeelWeb.Layouts). The layout reads @current_user/@flash directly,
  # so nothing needs to be forwarded from the templates.
  plug :put_layout, html: {ControlKeelWeb.Layouts, :public}

  def home(conn, _params) do
    render(conn, :home)
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started,
      install_channels: Skills.install_channels(),
      agent_integrations: Skills.agent_integrations()
    )
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end

  def privacy(conn, _params) do
    render(conn, :privacy)
  end

  def developers(conn, _params) do
    render(conn, :developers)
  end
end
