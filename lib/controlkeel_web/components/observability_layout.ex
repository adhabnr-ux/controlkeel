defmodule ControlKeelWeb.ObservabilityLayout do
  use ControlKeelWeb, :html

  @doc """
  Renders the observability layout with a persistent quick-links nav.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_path, :string,
    default: "",
    doc: "current request path for active link highlighting"

  slot :inner_block, required: true

  def observability(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
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
          <.link navigate={~p"/observability"} class={nav_link_class("/observability", @current_path)}>
            Overview
          </.link>
          <.link
            navigate={~p"/observability/loop"}
            class={nav_link_class("/observability/loop", @current_path)}
          >
            Learning loop
          </.link>
          <.link
            navigate={~p"/observability/promotions"}
            class={nav_link_class("/observability/promotions", @current_path)}
          >
            Promotions
          </.link>
          <.link
            navigate={~p"/observability/memory-quality"}
            class={nav_link_class("/observability/memory-quality", @current_path)}
          >
            Memory quality
          </.link>
          <.link
            navigate={~p"/observability/trends"}
            class={nav_link_class("/observability/trends", @current_path)}
          >
            Trends
          </.link>
          <.link
            navigate={~p"/observability/problems"}
            class={nav_link_class("/observability/problems", @current_path)}
          >
            Problems
          </.link>
          <.link
            navigate={~p"/observability/compare"}
            class={nav_link_class("/observability/compare", @current_path)}
          >
            Compare
          </.link>
          <.link
            navigate={~p"/observability/imports"}
            class={nav_link_class("/observability/imports", @current_path)}
          >
            Imports
          </.link>
          <.link
            navigate={~p"/observability/costs"}
            class={nav_link_class("/observability/costs", @current_path)}
          >
            Costs
          </.link>
          <.link
            navigate={~p"/observability/regressions"}
            class={nav_link_class("/observability/regressions", @current_path)}
          >
            Regressions
          </.link>
          <.link
            navigate={~p"/observability/evals"}
            class={nav_link_class("/observability/evals", @current_path)}
          >
            Evals
          </.link>
          <.link
            navigate={~p"/observability/evals/persisted"}
            class={nav_link_class("/observability/evals/persisted", @current_path)}
          >
            Saved evals
          </.link>
          <.link
            navigate={~p"/observability/benchmarks/drafts"}
            class={nav_link_class("/observability/benchmarks/drafts", @current_path)}
          >
            Drafts
          </.link>
          <.link
            navigate={~p"/observability/benchmarks/scenarios"}
            class={nav_link_class("/observability/benchmarks/scenarios", @current_path)}
          >
            Scenarios
          </.link>
          <.link
            navigate={~p"/observability/benchmarks/history"}
            class={nav_link_class("/observability/benchmarks/history", @current_path)}
          >
            History
          </.link>
          <.link
            navigate={~p"/observability/recommendations"}
            class={nav_link_class("/observability/recommendations", @current_path)}
          >
            Recommendations
          </.link>
        </div>

        {render_slot(@inner_block)}
      </section>
    </DashboardLayout.dashboard>
    """
  end

  defp nav_link_class(path, current_path) do
    active = path == current_path

    base = "text-sm font-medium transition-colors px-3 py-1.5 rounded-lg border"

    if active do
      "#{base} text-[var(--ck-lime)] bg-[rgba(190,242,100,0.1)] border-[var(--ck-lime)]"
    else
      "#{base} text-[var(--ck-text)] hover:text-[var(--ck-lime)] bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] border-[var(--ck-stroke)]"
    end
  end
end
