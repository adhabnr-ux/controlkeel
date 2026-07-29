defmodule ControlKeelWeb.ObservabilityBenchmarkScenariosLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    scenarios = Observability.observability_benchmark_scenarios(opts)
    run_preview = Observability.observability_benchmark_run_preview(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark Scenarios")
     |> assign(:scenarios, scenarios)
     |> assign(:run_preview, run_preview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-benchmark-scenarios-page"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-primary">
            Materialized benchmark scenarios
          </h1>
          <p class="text-muted-foreground text-sm mt-1">
            Local Benchmark.Scenario records generated from approved observability drafts.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span id="observability-benchmark-scenarios-count" class={neutral_pill_class()}>
            {@scenarios.count} scenario(s)
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs benchmarks scenarios" />

      <%= if @scenarios.recommendations != [] do %>
        <div id="observability-benchmark-scenarios-summary" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @scenarios.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div
        id="observability-benchmark-run-guidance"
        class="space-y-3"
      >
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Human-gated execution
        </p>
        <p class="text-muted-foreground text-sm leading-relaxed">
          Benchmark execution is CLI-only. Review generated scenarios first, then run an explicit command.
        </p>
        <code class="block rounded-lg border bg-[rgba(0,0,0,0.3)] px-3 py-2 text-xs text-muted-foreground overflow-x-auto">
          {@run_preview.command || "controlkeel obs benchmarks run --dry-run"}
        </code>
        <%= if @run_preview.recommendations != [] do %>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @run_preview.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <div id="observability-benchmark-scenarios-list" class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Scenarios
        </p>
        <%= if @scenarios.scenarios == [] do %>
          <p class="text-muted-foreground text-sm">
            No materialized observability scenarios yet.
          </p>
        <% else %>
          <%= for scenario <- @scenarios.scenarios do %>
            <div
              id={"observability-benchmark-scenario-#{scenario.id}"}
              class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-1"
            >
              <p class="text-sm font-semibold">{scenario.name}</p>
              <p class="text-muted-foreground text-xs">
                {scenario.suite_slug} · {scenario.slug} · {scenario.split}
              </p>
              <p class="text-muted-foreground text-xs">
                Expected rules: {Enum.join(scenario.expected_rules, ", ")}
              </p>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end
end
