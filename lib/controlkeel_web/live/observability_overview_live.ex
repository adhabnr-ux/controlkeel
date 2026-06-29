defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.SessionComponents

  @impl true
  def mount(_params, _session, socket) do
    overview = Observability.workspace_overview(limit: 9999)

    {:ok,
     socket
     |> assign(:page_title, "Observability")
     |> assign(:overview, overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability">
      <section id="observability-overview-page">
        <SessionComponents.session_observability_section runs={@overview.runs.recent} />
      </section>
    </ObservabilityLayout.observability>
    """
  end
end
