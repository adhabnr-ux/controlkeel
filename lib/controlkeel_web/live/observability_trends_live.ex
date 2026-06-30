defmodule ControlKeelWeb.ObservabilityTrendsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  use ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Observability trends")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, load_trends(socket, parse_days(params["days"]))}
  end

  @impl true
  def handle_event("select_days", %{"days" => days}, socket) do
    {:noreply, push_patch(socket, to: ~p"/observability/trends?#{[days: parse_days(days)]}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/trends">
      <section
        id="observability-trends"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Trends</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Local run, finding, cost, and import trends across a rolling N-day window.
            </p>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <form id="trends-days" phx-change="select_days">
              <select
                name="days"
                class="border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7] outline-none cursor-pointer appearance-none"
                style="padding-right: 1.75rem; background-image: url('data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%2212%22 height=%2212%22 viewBox=%220 0 24 24%22 fill=%22none%22 stroke=%22%23d2ffe7%22 stroke-width=%222%22 stroke-linecap=%22round%22 stroke-linejoin=%22round%22%3E%3Cpolyline points=%226 9 12 15 18 9%22%3E%3C/polyline%3E%3C/svg%3E'); background-repeat: no-repeat; background-position: right 0.5rem center; background-size: 14px;"
              >
                <option value="1" selected={@selected_days == 1}>Today</option>
                <option value="3" selected={@selected_days == 3}>3 days</option>
                <option value="7" selected={@selected_days == 7}>1 week</option>
                <option value="30" selected={@selected_days == 30}>1 month</option>
              </select>
            </form>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs trends --days [N]" />
        <div class="text-[var(--ck-muted)] text-xs">
          example: <span class="text-[var(--ck-lime)]">controlkeel obs trends --days 30</span>
          <span class="opacity-60">• controlkeel obs trends (no flag) defaults to 7 days</span>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div
            id="observability-trends-runs"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Runs</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@trends.totals.runs}</p>
            <p class="text-[var(--ck-muted)] text-xs">
              {@trends.totals.red_runs} red · {@trends.totals.yellow_runs} yellow · {@trends.totals.green_runs} green
            </p>
          </div>
          <div
            id="observability-trends-findings"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Findings</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@trends.totals.active_findings}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">{@trends.totals.blocked_findings} blocked</p>
          </div>
          <div
            id="observability-trends-costs"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Estimated spend
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {format_currency(@trends.totals.estimated_cost_cents)}
            </p>
          </div>
          <div
            id="observability-trends-imports"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Imports</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@trends.totals.imports}</p>
            <p class="text-[var(--ck-muted)] text-xs">
              {@trends.totals.verified_imports} verified · {@trends.totals.non_verified_imports} non-verified
            </p>
          </div>
        </div>

        <%= if @trends.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <ul class="list-disc pl-5">
              <%= for recommendation <- @trends.recommendations do %>
                <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <div class="space-y-4">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Daily series
          </p>
          <div class="space-y-3 max-h-[650px] overflow-y-auto">
            <%= for day <- @trends.series do %>
              <div
                id={"observability-trend-#{day.date}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <p class="text-sm font-semibold text-[var(--ck-text)]">{day.date}</p>
                <p class="text-[var(--ck-muted)] text-xs">
                  Runs {day.runs} · red {day.health.red} · yellow {day.health.yellow} · green {day.health.green}
                </p>
                <div class="h-1.5 overflow-hidden rounded-full bg-[rgba(255,255,255,0.06)]">
                  <div
                    class="h-full rounded-full bg-[#ff6b6b]"
                    style={"width: #{bar_width(day.health.red, @trends.totals.runs)}%"}
                  >
                  </div>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">
                  Findings {day.active_findings} / {day.blocked_findings} blocked · cost {format_currency(
                    day.estimated_cost_cents
                  )} · imports {day.imports} ({day.verified_imports} verified)
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp load_trends(socket, days) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()

    opts =
      if recent_session,
        do: [workspace_id: recent_session.workspace_id, days: days],
        else: [days: days]

    socket
    |> assign(:trends, Observability.trends(opts))
    |> assign(:selected_days, days)
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
