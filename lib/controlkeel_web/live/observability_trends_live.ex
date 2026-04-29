defmodule ControlKeelWeb.ObservabilityTrendsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    days = parse_days(params["days"])

    opts =
      if recent_session,
        do: [workspace_id: recent_session.workspace_id, days: days],
        else: [days: days]

    trends = Observability.trends(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability trends")
     |> assign(:trends, trends)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-trends-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Local trends</h1>
            <p class="ck-lead ck-lead-tight">
              Read-only daily trends for runs, findings, cost, and persisted imports.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-trends-window" class="ck-pill ck-pill-neutral">
              {@trends.days} day window
            </span>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-trends-runs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Runs</p>
            <strong>{@trends.totals.runs}</strong>
            <p class="ck-note">
              {@trends.totals.red_runs} red · {@trends.totals.yellow_runs} yellow · {@trends.totals.green_runs} green
            </p>
          </div>
          <div id="observability-trends-findings" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Findings</p>
            <strong>{@trends.totals.active_findings}</strong>
            <p class="ck-note">{@trends.totals.blocked_findings} blocked</p>
          </div>
          <div id="observability-trends-costs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Estimated spend</p>
            <strong>{format_currency(@trends.totals.estimated_cost_cents)}</strong>
          </div>
          <div id="observability-trends-imports" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Imports</p>
            <strong>{@trends.totals.imports}</strong>
            <p class="ck-note">
              {@trends.totals.verified_imports} verified · {@trends.totals.non_verified_imports} non-verified
            </p>
          </div>
        </div>

        <div id="observability-trends-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @trends.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-trends-series" class="ck-card">
          <p class="ck-mini-label">Daily series</p>
          <ul class="ck-mini-list">
            <%= for day <- @trends.series do %>
              <li id={"observability-trend-#{day.date}"}>
                <strong>{day.date}</strong>
                <p class="ck-note">
                  Runs {day.runs} · red {day.health.red} · yellow {day.health.yellow} · green {day.health.green}
                </p>
                <div class="mt-2 h-2 overflow-hidden rounded-full bg-slate-200">
                  <div
                    class="h-full rounded-full bg-rose-500"
                    style={"width: #{bar_width(day.health.red, @trends.totals.runs)}%"}
                  >
                  </div>
                </div>
                <p class="ck-note">
                  Findings {day.active_findings} / {day.blocked_findings} blocked · cost {format_currency(
                    day.estimated_cost_cents
                  )} · imports {day.imports} ({day.verified_imports} verified)
                </p>
              </li>
            <% end %>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp parse_days(nil), do: 7

  defp parse_days(value) do
    case Integer.parse(to_string(value)) do
      {days, ""} when days > 0 -> days
      _ -> 7
    end
  end

  defp bar_width(_value, 0), do: 0
  defp bar_width(value, total), do: min(100, round(value * 100 / total))

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
