defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

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
