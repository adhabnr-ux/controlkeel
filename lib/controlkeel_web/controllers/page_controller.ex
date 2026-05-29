defmodule ControlKeelWeb.PageController do
  use ControlKeelWeb, :controller

  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.RuntimeMode

  def home(conn, _params) do
    render(conn, :home,
      benchmark_summary: Benchmark.benchmark_summary(),
      recent_sessions: Mission.list_recent_sessions(),
      ship_summary: Analytics.funnel_summary(),
      runtime_mode: RuntimeMode.current(),
      current_user: conn.assigns[:current_user]
    )
  end

  def getting_started(conn, _params) do
    render(conn, :getting_started)
  end
end
