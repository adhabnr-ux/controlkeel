defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    overview = Observability.workspace_overview(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability")
     |> assign(:overview, overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-overview-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Workspace overview</h1>
            <p class="ck-lead ck-lead-tight">
              Local-first run health, grouped problems, costs, and trace export posture.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span
              id="observability-overview-health"
              class={health_pill_class(@overview.health.status)}
            >
              {@overview.health.status}
            </span>
            <span class="ck-pill ck-pill-neutral">{@overview.runs.count} recent runs</span>
            <.link navigate={~p"/observability/recommendations"} class="ck-link">
              Recommendations
            </.link>
            <.link navigate={~p"/observability/evals"} class="ck-link">Eval candidates</.link>
            <.link navigate={~p"/observability/compare"} class="ck-link">Compare</.link>
            <.link navigate={~p"/observability/imports"} class="ck-link">Imports</.link>
            <.link navigate={~p"/observability/problems"} class="ck-link">Open problems</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-overview-runs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Runs</p>
            <strong>{@overview.runs.count} recent</strong>
            <p class="ck-note">
              {@overview.health.red_runs} red · {@overview.health.yellow_runs} yellow · {@overview.health.green_runs} green
            </p>
          </div>

          <div id="observability-overview-problems" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Problems</p>
            <strong>{@overview.problems.count} groups</strong>
            <p class="ck-note">{@overview.problems.total_findings} active finding(s)</p>
            <.link navigate={~p"/observability/problems"} class="ck-link">Review groups</.link>
          </div>

          <div id="observability-overview-costs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Costs</p>
            <strong>
              {format_currency(@overview.costs.spent_cents)} / {format_currency(
                @overview.costs.budget_cents
              )}
            </strong>
            <p class="ck-note">
              {@overview.costs.invocations} invocation(s), {format_currency(
                @overview.costs.estimated_invocation_cents
              )} estimated
            </p>
            <.link navigate={~p"/observability/costs"} class="ck-link">Review costs</.link>
          </div>

          <div id="observability-overview-telemetry" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Trace export</p>
            <strong>{@overview.telemetry.import_mode}</strong>
            <p class="ck-note">
              {@overview.telemetry.export_schema_version} · {@overview.telemetry.integrity}
            </p>
            <p class="ck-note">{@overview.telemetry.persisted_imports} persisted import(s)</p>
            <.link navigate={~p"/observability/imports"} class="ck-link">Review imports</.link>
          </div>
        </div>

        <div id="observability-overview-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommended next actions</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @overview.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
          <.link navigate={~p"/observability/recommendations"} class="ck-link">
            Open recommendations
          </.link>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div id="observability-overview-run-list" class="ck-card">
            <p class="ck-mini-label">Recent session runs</p>
            <%= if @overview.runs.recent == [] do %>
              <p class="ck-note">No session runs available yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for run <- @overview.runs.recent do %>
                  <li>
                    <strong>{run.title}</strong>
                    <p class="ck-note">
                      {run.health} · {run.active_findings} active finding(s) · {run.pending_gates} gate(s)
                      <.link navigate={~p"/observability/sessions/#{run.id}"} class="ck-link">
                        Open run
                      </.link>
                      <.link href={~p"/observability/sessions/#{run.id}/export.json"} class="ck-link">
                        Export
                      </.link>
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div id="observability-overview-problem-list" class="ck-card">
            <p class="ck-mini-label">Top problems</p>
            <%= if @overview.problems.top == [] do %>
              <p class="ck-note">No active problems detected.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for problem <- @overview.problems.top do %>
                  <li>
                    <strong>{problem.rule_id}</strong>
                    <p class="ck-note">
                      {problem.health} · {problem.count} finding(s) · {problem.affected_session_count} session(s)
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp health_pill_class(_), do: "ck-pill ck-pill-low"

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
