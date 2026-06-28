defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    overview = Observability.workspace_overview(limit: 9999)

    {:ok,
     socket
     |> assign(:page_title, "Observability")
     |> assign(:overview, overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section
        id="observability-overview-page"
        class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16"
      >
        <div class="space-y-1">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Observability
          </h2>
          <p class="text-[var(--ck-muted)]">
            Session health and workspace observability signals.
          </p>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-6">
          <p class="">Quick links</p>

          <div class="flex gap-4 flex-wrap mt-4">
            <.link
              navigate={~p"/observability/loop"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Learning loop
            </.link>
            <.link
              navigate={~p"/observability/recommendations"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Recommendations
            </.link>
            <.link
              navigate={~p"/observability/evals"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Eval candidates
            </.link>
            <.link
              navigate={~p"/observability/evals/persisted"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Saved evals
            </.link>
            <.link
              navigate={~p"/observability/benchmarks/drafts"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Benchmark drafts
            </.link>
            <.link
              navigate={~p"/observability/benchmarks/history"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Benchmark history
            </.link>
            <.link
              navigate={~p"/observability/promotions"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Promotions
            </.link>
            <.link
              navigate={~p"/observability/regressions"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Regressions
            </.link>
            <.link
              navigate={~p"/observability/compare"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Compare
            </.link>
            <.link
              navigate={~p"/observability/imports"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Imports
            </.link>
            <.link
              navigate={~p"/observability/memory-quality"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Memory quality
            </.link>
            <.link
              navigate={~p"/observability/trends"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Trends
            </.link>
            <.link
              navigate={~p"/observability/problems"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Open problems
            </.link>
          </div>
        </div>

        <div
          id="observability-overview-run-list"
          class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6"
        >
          <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-4">
            Session observability
          </p>
          <%= if @overview.runs.recent == [] do %>
            <p class="text-[var(--ck-muted)]">No sessions available yet.</p>
          <% else %>
            <ul class="grid gap-3 m-0 p-0 list-none">
              <%= for run <- @overview.runs.recent do %>
                <li class="flex items-center gap-3 border-b border-[var(--ck-stroke)] pb-3 last:border-b-0 last:pb-0">
                  <.link
                    navigate={~p"/observability/sessions/#{run.id}"}
                    class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors no-underline min-w-0 flex-1 truncate"
                  >
                    {run.title}
                  </.link>
                  <span class={health_badge_class(run.health)}>{run.health}</span>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_badge_class("red"),
    do: "text-xs font-medium px-2 py-0.5 rounded-full bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp health_badge_class("yellow"),
    do: "text-xs font-medium px-2 py-0.5 rounded-full bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp health_badge_class(_),
    do: "text-xs font-medium px-2 py-0.5 rounded-full bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
end
