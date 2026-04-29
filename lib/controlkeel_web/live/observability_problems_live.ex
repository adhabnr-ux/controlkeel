defmodule ControlKeelWeb.ObservabilityProblemsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []

    {:ok,
     socket
     |> assign(:page_title, "Observability Problems")
     |> assign(:problems, Observability.problems(opts))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-problems-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Problems</h1>
            <p class="ck-lead ck-lead-tight">
              Sentry-style grouping for active ControlKeel findings, linked back to affected session runs.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span class={health_pill_class(@problems.health)}>{@problems.health}</span>
            <span class="ck-pill ck-pill-neutral">{@problems.count} groups</span>
          </div>
        </div>

        <div id="observability-problem-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @problems.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-problem-list" class="ck-grid ck-grid-dashboard">
          <%= if @problems.problems == [] do %>
            <div class="ck-card">
              <p class="ck-note">No active problems detected.</p>
            </div>
          <% else %>
            <%= for problem <- @problems.problems do %>
              <div id={"observability-problem-#{problem_key_id(problem.key)}"} class="ck-card">
                <div class="ck-section-header" style="margin-bottom: 1rem;">
                  <div>
                    <p class="ck-mini-label">{problem.category}</p>
                    <h2 style="margin: 0; font-size: 1.15rem;">{problem.rule_id}</h2>
                    <p class="ck-note" style="margin: 0.35rem 0 0;">{problem.title}</p>
                  </div>
                  <span class={health_pill_class(problem.health)}>{problem.health}</span>
                </div>

                <div class="ck-brief-grid">
                  <div>
                    <h3>Severity</h3>
                    <p class="ck-note">{problem.severity}</p>
                  </div>
                  <div>
                    <h3>Count</h3>
                    <p class="ck-note">{problem.count}</p>
                  </div>
                  <div>
                    <h3>Affected sessions</h3>
                    <p class="ck-note">{problem.affected_session_count}</p>
                  </div>
                  <div>
                    <h3>Last seen</h3>
                    <p class="ck-note">{problem.last_seen || "unknown"}</p>
                  </div>
                </div>

                <p class="ck-mini-label" style="margin-top: 1rem;">Next action</p>
                <p class="ck-note">{problem.recommendation}</p>

                <div
                  id={"observability-problem-feedback-#{problem_key_id(problem.key)}"}
                  class="ck-card"
                  style="margin-top: 1rem;"
                >
                  <p class="ck-mini-label">Feedback loop</p>
                  <div class="ck-brief-grid">
                    <div>
                      <h3>Eval candidate</h3>
                      <p class="ck-note">{problem.feedback_loop.eval_candidate_title}</p>
                    </div>
                    <div>
                      <h3>Evidence</h3>
                      <p class="ck-note">{problem.feedback_loop.evidence_summary}</p>
                    </div>
                    <div>
                      <h3>Benchmark hint</h3>
                      <p class="ck-note">{problem.feedback_loop.benchmark_hint}</p>
                    </div>
                    <div>
                      <h3>Human gate</h3>
                      <p class="ck-note">
                        {if problem.feedback_loop.human_gate_required,
                          do: "required",
                          else: "not required"}
                      </p>
                    </div>
                  </div>
                  <p class="ck-note" style="margin-top: 0.75rem;">
                    {problem.feedback_loop.suggested_action}
                  </p>
                  <.link navigate={~p"/benchmarks"} class="ck-link">Open benchmarks</.link>
                </div>

                <p class="ck-mini-label" style="margin-top: 1rem;">Examples</p>
                <ul class="ck-mini-list">
                  <%= for example <- problem.examples do %>
                    <li>
                      <strong>{example.title}</strong>
                      <p class="ck-note">
                        {example.severity} / {example.status} · session #{example.session_id}
                        <.link
                          navigate={~p"/observability/sessions/#{example.session_id}"}
                          class="ck-link"
                        >
                          Open run
                        </.link>
                      </p>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp health_pill_class(_), do: "ck-pill ck-pill-low"

  defp problem_key_id(key) do
    key
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
