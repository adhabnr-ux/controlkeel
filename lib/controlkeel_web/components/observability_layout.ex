defmodule ControlKeelWeb.ObservabilityLayout do
  use ControlKeelWeb, :html

  @doc """
  Renders the observability layout with a persistent quick-links nav.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  slot :inner_block, required: true

  def observability(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16">
        <div class="space-y-1 mb-8">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Observability
          </h2>
          <p class="text-[var(--ck-muted)]">
            Session health and workspace observability signals.
          </p>
        </div>

        <div class="flex gap-3 flex-wrap mb-4">
          <.link
            navigate={~p"/observability"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Overview
          </.link>
          <.link
            navigate={~p"/observability/loop"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Learning loop
          </.link>

          <.link
            navigate={~p"/observability/promotions"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Promotions
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
            navigate={~p"/observability/costs"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Costs
          </.link>
          <.link
            navigate={~p"/observability/regressions"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Regressions
          </.link>
          <.link
            navigate={~p"/observability/recommendations"}
            class="text-sm font-medium text-[var(--ck-text)] hover:text-[var(--ck-lime)] transition-colors bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] px-3 py-1.5 rounded-lg border border-[var(--ck-stroke)]"
          >
            Recommendations
          </.link>
        </div>

        {render_slot(@inner_block)}
      </section>
    </Layouts.app>
    """
  end
end
