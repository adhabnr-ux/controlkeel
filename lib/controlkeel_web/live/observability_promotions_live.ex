defmodule ControlKeelWeb.ObservabilityPromotionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    promotions = Observability.promotion_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Promotion Candidates")
     |> assign(:promotions, promotions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-promotions-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Promotion candidates</h1>
            <p class="ck-lead ck-lead-tight">
              Advisory, human-gated promotion candidates backed by local observability evidence.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-promotions-count" class="ck-pill ck-pill-neutral">
              {@promotions.count} candidate(s)
            </span>
            <.link navigate={~p"/observability/benchmarks/history"} class="ck-link">History</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-promotions-summary" class="ck-card">
          <p class="ck-mini-label">Execution boundary</p>
          <strong>Promotion execution: {@promotions.promotion_execution}</strong>
          <p class="ck-note">
            This page does not mutate policy, router, prompt, or autofix artifacts.
          </p>
        </div>

        <div id="observability-promotions-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @promotions.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-promotions-list" class="ck-card">
          <%= if @promotions.candidates == [] do %>
            <p class="ck-note">No promotion candidates yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for candidate <- @promotions.candidates do %>
                <li id={"observability-promotion-candidate-#{candidate.id}"}>
                  <strong>{candidate.rule_id}</strong>
                  <span class="ck-pill ck-pill-neutral">{candidate.readiness}</span>
                  <p class="ck-note">{candidate.suggested_action}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
