defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker

  def home(conn, _params) do
    project_root = conn.private.phoenix_endpoint.config(:project_root) || File.cwd!()

    render(conn, :home,
      benchmark_summary: Benchmark.benchmark_summary(),
      provider_status: ProviderBroker.status(project_root),
      recent_sessions: Mission.list_recent_sessions(4),
      ship_summary: Analytics.funnel_summary()
    )
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started)
  end
end
