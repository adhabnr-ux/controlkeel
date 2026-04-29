defmodule ControlKeelWeb.ObservabilityRecommendationsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    recommendations = Observability.recommendations(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Recommendations")
     |> assign(:recommendations, recommendations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-recommendations-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Recommendations</h1>
            <p class="ck-lead ck-lead-tight">
              Prioritized local next actions from runs, problems, costs, and proof signals.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span
              id="observability-recommendations-health"
              class={health_pill_class(@recommendations.health)}
            >
              {@recommendations.health}
            </span>
            <span class="ck-pill ck-pill-neutral">{@recommendations.count} action(s)</span>
            <.link navigate={~p"/observability/evals"} class="ck-link">Eval candidates</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-recommendations-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Actions</p>
            <strong>{@recommendations.count}</strong>
            <p class="ck-note">Prioritized by current local evidence</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Categories</p>
            <strong>{length(@recommendations.categories)}</strong>
            <p class="ck-note">{Enum.join(@recommendations.categories, ", ")}</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Workspace</p>
            <strong>{@recommendations.workspace.name}</strong>
            <p class="ck-note">Local-first summary</p>
          </div>
        </div>

        <div id="observability-recommendations-list" class="ck-card">
          <%= if @recommendations.actions == [] do %>
            <p class="ck-note">No recommendations are currently active.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for action <- @recommendations.actions do %>
                <li id={"observability-recommendation-#{action.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{action.category}</p>
                      <strong>{action.title}</strong>
                    </div>
                    <span class={priority_pill_class(action.priority)}>{action.priority}</span>
                  </div>
                  <p class="ck-note">{action.evidence}</p>
                  <p>{action.suggested_action}</p>
                  <p class="ck-note">
                    Source: {action.source} · Human gate required: {action.human_gate_required}
                  </p>
                  <.link navigate={action.link} class="ck-link">Open related view</.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp health_pill_class(_), do: "ck-pill ck-pill-low"

  defp priority_pill_class("critical"), do: "ck-pill ck-pill-critical"
  defp priority_pill_class("high"), do: "ck-pill ck-pill-warning"
  defp priority_pill_class(_), do: "ck-pill ck-pill-neutral"
end
