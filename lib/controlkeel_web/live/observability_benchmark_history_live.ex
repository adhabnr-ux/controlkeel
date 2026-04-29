defmodule ControlKeelWeb.ObservabilityBenchmarkHistoryLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    history = Observability.observability_benchmark_history(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark History")
     |> assign(:history, history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-benchmark-history-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Benchmark history</h1>
            <p class="ck-lead ck-lead-tight">
              Read-only readiness and run evidence for generated observability benchmark scenarios.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-benchmark-history-readiness" class="ck-pill ck-pill-neutral">
              {@history.readiness.status}
            </span>
            <.link navigate={~p"/observability/benchmarks/scenarios"} class="ck-link">
              Scenarios
            </.link>
            <.link navigate={~p"/observability/benchmarks/drafts"} class="ck-link">Drafts</.link>
            <.link navigate={~p"/observability/promotions"} class="ck-link">Promotions</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-benchmark-history-summary" class="ck-card">
          <p class="ck-mini-label">Readiness</p>
          <strong>{@history.readiness.reason}</strong>
          <div class="ck-stat-grid">
            <div class="ck-stat-card">Saved evals: {@history.coverage.saved_eval_candidates}</div>
            <div class="ck-stat-card">Drafts: {@history.coverage.benchmark_drafts}</div>
            <div class="ck-stat-card">Materialized: {@history.coverage.materialized_scenarios}</div>
            <div class="ck-stat-card">Covered: {@history.coverage.covered_scenarios}</div>
          </div>
        </div>

        <div id="observability-benchmark-history-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @history.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-benchmark-history-runs" class="ck-card">
          <p class="ck-mini-label">Recent generated-suite runs</p>
          <%= if @history.runs == [] do %>
            <p class="ck-note">No observability benchmark runs yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for run <- @history.runs do %>
                <li id={"observability-benchmark-history-run-#{run.id}"}>
                  <strong>Run #{run.id}: {run.status}</strong>
                  <p class="ck-note">
                    {run.suite} · catch {run.catch_rate}% · rule-hit {run.expected_rule_hit_rate}%
                  </p>
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
