defmodule ControlKeelWeb.ObservabilityBenchmarkHistoryLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    history = Observability.observability_benchmark_history(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark History")
     |> assign(:history, history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-benchmark-history-page"
      class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Benchmark history</h1>
          <p class="text-[var(--ck-muted)] text-sm mt-1">
            Read-only readiness and run evidence for generated observability benchmark scenarios.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span id="observability-benchmark-history-readiness" class={neutral_pill_class()}>
            {@history.readiness.status}
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs benchmarks history" />

      <div
        id="observability-benchmark-history-summary"
        class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-4"
      >
        <div class="space-y-1">
          <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Readiness</p>
          <p class="text-base font-semibold text-[var(--ck-text)]">{@history.readiness.reason}</p>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="rounded-lg p-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.02)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Saved evals</p>
            <p class="text-xl font-semibold text-[var(--ck-text)]">
              {@history.coverage.saved_eval_candidates}
            </p>
          </div>
          <div class="rounded-lg p-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.02)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Drafts</p>
            <p class="text-xl font-semibold text-[var(--ck-text)]">
              {@history.coverage.benchmark_drafts}
            </p>
          </div>
          <div class="rounded-lg p-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.02)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Materialized
            </p>
            <p class="text-xl font-semibold text-[var(--ck-text)]">
              {@history.coverage.materialized_scenarios}
            </p>
          </div>
          <div class="rounded-lg p-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.02)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Covered</p>
            <p class="text-xl font-semibold text-[var(--ck-text)]">
              {@history.coverage.covered_scenarios}
            </p>
          </div>
        </div>
      </div>

      <%= if @history.recommendations != [] do %>
        <div id="observability-benchmark-history-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @history.recommendations do %>
              <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div id="observability-benchmark-history-runs" class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
          Recent generated-suite runs
        </p>
        <%= if @history.runs == [] do %>
          <p class="text-[var(--ck-muted)] text-sm">No observability benchmark runs yet.</p>
        <% else %>
          <%= for run <- @history.runs do %>
            <div
              id={"observability-benchmark-history-run-#{run.id}"}
              class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                    {run.suite}
                  </p>
                  <p class="text-sm font-semibold text-[var(--ck-text)]">
                    Run #{run.id}: {run.status}
                  </p>
                </div>
              </div>
              <p class="text-[var(--ck-muted)] text-xs">
                catch {run.catch_rate}% · rule-hit {run.expected_rule_hit_rate}%
              </p>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end
end
