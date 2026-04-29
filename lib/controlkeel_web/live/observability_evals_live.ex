defmodule ControlKeelWeb.ObservabilityEvalsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    eval_candidates = Observability.eval_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Eval Candidates")
     |> assign(:eval_candidates, eval_candidates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-evals-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Eval candidates</h1>
            <p class="ck-lead ck-lead-tight">
              Advisory regression candidates derived from grouped problems and feedback evidence.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-evals-health" class={health_pill_class(@eval_candidates.health)}>
              {@eval_candidates.health}
            </span>
            <span class="ck-pill ck-pill-neutral">{@eval_candidates.count} candidate(s)</span>
            <.link navigate={~p"/observability/recommendations"} class="ck-link">
              Recommendations
            </.link>
            <.link navigate={~p"/observability/evals/persisted"} class="ck-link">
              Saved candidates
            </.link>
          </div>
        </div>

        <div id="observability-evals-summary" class="ck-card">
          <p class="ck-mini-label">Recommended next actions</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @eval_candidates.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-evals-list" class="ck-card">
          <%= if @eval_candidates.candidates == [] do %>
            <p class="ck-note">No eval candidates are currently active.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for candidate <- @eval_candidates.candidates do %>
                <li id={"observability-eval-#{candidate.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{candidate.category}</p>
                      <strong>{candidate.title}</strong>
                    </div>
                    <span class={priority_pill_class(candidate.priority)}>
                      {candidate.priority}
                    </span>
                  </div>
                  <p class="ck-note">
                    {candidate.rule_id} · {candidate.finding_count} finding(s) · {candidate.affected_session_count} session(s)
                  </p>
                  <p>{candidate.evidence_summary}</p>
                  <p class="ck-note">Benchmark hint: {candidate.benchmark_hint}</p>
                  <p class="ck-note">
                    Human gate required: {candidate.human_gate_required}
                  </p>
                  <.link navigate={candidate.links.problems} class="ck-link">
                    Open problem groups
                  </.link>
                  <.link navigate={candidate.links.benchmarks} class="ck-link">Open benchmarks</.link>
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
