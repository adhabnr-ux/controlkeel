defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.SessionComponents

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
        <div class="space-y-1 mb-8">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Observability
          </h2>
          <p class="text-[var(--ck-muted)]">
            Session health and workspace observability signals.
          </p>
        </div>

        <div class="space-y-8">
          <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold mb-4">
              Quick links
            </p>

            <div class="flex gap-3 flex-wrap">
              <.link
                navigate={~p"/observability/loop"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Learning loop
              </.link>
              <.link
                navigate={~p"/observability/recommendations"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Recommendations
              </.link>
              <.link
                navigate={~p"/observability/evals"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Eval candidates
              </.link>
              <.link
                navigate={~p"/observability/evals/persisted"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Saved evals
              </.link>
              <.link
                navigate={~p"/observability/benchmarks/drafts"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Benchmark drafts
              </.link>
              <.link
                navigate={~p"/observability/benchmarks/history"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Benchmark history
              </.link>
              <.link
                navigate={~p"/observability/promotions"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Promotions
              </.link>
              <.link
                navigate={~p"/observability/regressions"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Regressions
              </.link>
              <.link
                navigate={~p"/observability/compare"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Compare
              </.link>
              <.link
                navigate={~p"/observability/imports"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Imports
              </.link>
              <.link
                navigate={~p"/observability/memory-quality"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Memory quality
              </.link>
              <.link
                navigate={~p"/observability/trends"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Trends
              </.link>
              <.link
                navigate={~p"/observability/problems"}
                class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
              >
                Open problems
              </.link>
            </div>
          </div>

          <SessionComponents.session_observability_section runs={@overview.runs.recent} />
        </div>
      </section>
    </Layouts.app>
    """
  end
end
