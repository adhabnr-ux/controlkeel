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
      <section
        id="observability-trends"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-6">
            Trends
          </p>
          <div class="flex items-center gap-3">
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@trends.days} day window
            </span>
            <.link
              navigate={~p"/observability"}
              class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
            >
              Overview →
            </.link>
          </div>
        </div>

        <div class="text-[var(--ck-muted)] text-xs font-mono border border-[var(--ck-stroke)] rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
          controlkeel obs trends
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
            <%= for recommendation <- @trends.recommendations do %>
              <p class="text-[var(--ck-text)] text-sm leading-relaxed">{recommendation}</p>
            <% end %>
          </div>
        <% end %>

        <div class="space-y-4">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Daily series
          </p>
          <div class="space-y-3">
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
