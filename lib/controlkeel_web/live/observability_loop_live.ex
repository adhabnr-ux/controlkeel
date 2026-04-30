defmodule ControlKeelWeb.ObservabilityLoopLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    loop = Observability.loop_status(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Learning Loop")
     |> assign(:loop, loop)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-loop-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Learning loop</h1>
            <p class="ck-lead ck-lead-tight">
              Read-only, local-first status for turning repeated CK and agent use into reviewed evals, benchmark evidence, and human-gated improvement candidates.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-loop-health" class={health_pill_class(@loop.health)}>
              {@loop.health}
            </span>
            <span id="observability-loop-mode" class="ck-pill ck-pill-neutral">
              {@loop.learning_loop.mode}
            </span>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
            <.link navigate={~p"/observability/benchmarks/history"} class="ck-link">History</.link>
            <.link navigate={~p"/observability/promotions"} class="ck-link">Promotions</.link>
          </div>
        </div>

        <div id="observability-loop-boundary" class="ck-card">
          <p class="ck-mini-label">Safety boundary</p>
          <strong>Read-only: {@loop.read_only} · Mutation: {@loop.mutation}</strong>
          <p class="ck-note">
            Automatic benchmark execution: {@loop.learning_loop.automatic_benchmark_execution} · Automatic promotion: {@loop.learning_loop.automatic_promotion}
          </p>
          <p class="ck-note">Generated benchmarks are {@loop.learning_loop.generated_benchmarks}.</p>
        </div>

        <div id="observability-loop-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Problems</p>
            <strong>{@loop.active_problems.count} group(s)</strong>
            <p class="ck-note">{@loop.active_problems.total_findings} active finding(s)</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Evals</p>
            <strong>{@loop.evals.derived} derived / {@loop.evals.saved} saved</strong>
            <p class="ck-note">Saved status: {format_frequency(@loop.evals.saved_by_status)}</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Benchmarks</p>
            <strong>{@loop.benchmarks.scenarios} scenario(s)</strong>
            <p class="ck-note">
              {@loop.benchmarks.drafts} draft(s), readiness {@loop.benchmarks.history_readiness.status}
            </p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Promotions</p>
            <strong>{@loop.promotions.count} candidate(s)</strong>
            <p class="ck-note">Readiness: {format_frequency(@loop.promotions.by_readiness)}</p>
          </div>
        </div>

        <div id="observability-loop-blockers" class="ck-card">
          <p class="ck-mini-label">Blockers</p>
          <%= if @loop.blockers == [] do %>
            <p class="ck-note">No learning-loop blockers detected.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for blocker <- @loop.blockers do %>
                <li><strong>{blocker.id}</strong>: {blocker.reason}</li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <div id="observability-loop-actions" class="ck-card">
          <p class="ck-mini-label">Next actions</p>
          <ul class="ck-mini-list">
            <%= for action <- @loop.next_actions do %>
              <li>[{action.priority}] {action.title}: {action.suggested_action}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-loop-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @loop.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp health_pill_class(_), do: "ck-pill ck-pill-low"

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
