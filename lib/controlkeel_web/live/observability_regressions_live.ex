defmodule ControlKeelWeb.ObservabilityRegressionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    regressions = Observability.regressions(opts)

    {:ok,
     socket
     |> assign(:page_title, "Regression Tracking")
     |> assign(:regressions, regressions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-regressions-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Regression tracking</h1>
            <p class="ck-lead ck-lead-tight">
              Read-only benchmark run posture connected to saved eval candidates and benchmark drafts.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span
              id="observability-regressions-health"
              class={health_pill_class(@regressions.health.status)}
            >
              {@regressions.health.status}
            </span>
            <.link navigate={~p"/observability/benchmarks/drafts"} class="ck-link">
              Benchmark drafts
            </.link>
            <.link navigate={~p"/benchmarks"} class="ck-link">Benchmarks</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-regressions-runs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Benchmark runs</p>
            <strong>{@regressions.benchmark_runs.count}</strong>
            <p class="ck-note">Window: {@regressions.days} day(s)</p>
          </div>
          <div id="observability-regressions-catch-rate" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Average catch rate</p>
            <strong>{format_rate(@regressions.benchmark_runs.average_catch_rate)}</strong>
            <p class="ck-note">{format_frequency(@regressions.benchmark_runs.by_status)}</p>
          </div>
          <div id="observability-regressions-draft-coverage" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Draft coverage</p>
            <strong>{@regressions.draft_coverage.benchmark_drafts} draft(s)</strong>
            <p class="ck-note">{@regressions.draft_coverage.saved_eval_candidates} saved eval(s)</p>
          </div>
        </div>

        <div id="observability-regressions-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <p class="ck-note">{@regressions.health.reason}</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @regressions.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-regressions-runs-list" class="ck-card">
          <p class="ck-mini-label">Recent benchmark runs</p>
          <%= if @regressions.benchmark_runs.recent == [] do %>
            <p class="ck-note">No benchmark runs in the selected window.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for run <- @regressions.benchmark_runs.recent do %>
                <li id={"observability-regression-run-#{run.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{run.suite}</p>
                      <strong>Run #{run.id}</strong>
                    </div>
                    <span class="ck-pill ck-pill-neutral">{run.status}</span>
                  </div>
                  <p class="ck-note">
                    Catch rate {format_rate(run.catch_rate)} · {run.caught_count}/{run.total_scenarios} scenario(s) · {run.result_count} result(s)
                  </p>
                  <.link navigate={~p"/benchmarks/runs/#{run.id}"} class="ck-link">Open run</.link>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) do
    map
    |> Enum.sort_by(fn {key, _count} -> key end)
    |> Enum.map_join(", ", fn {key, count} -> "#{key}: #{count}" end)
  end

  defp format_rate(nil), do: "0.0%"
  defp format_rate(rate), do: "#{Float.round(rate * 100, 1)}%"

  defp health_pill_class("red"), do: "ck-pill ck-pill-red"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-yellow"
  defp health_pill_class(_status), do: "ck-pill ck-pill-green"
end
