defmodule ControlKeelWeb.ObservabilityRegressionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

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
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/regressions">
      <section
        id="observability-regressions"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Regression tracking</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Read-only benchmark run posture connected to saved eval candidates and benchmark drafts.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class={health_pill_class(@regressions.health.status)}>
              {@regressions.health.status}
            </span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs regressions" />

        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div
            id="observability-regressions-runs"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Benchmark runs
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@regressions.benchmark_runs.count}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">Window: {@regressions.days} day(s)</p>
          </div>
          <div
            id="observability-regressions-catch-rate"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Average catch rate
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {format_rate(@regressions.benchmark_runs.average_catch_rate)}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">
              {format_frequency(@regressions.benchmark_runs.by_status)}
            </p>
          </div>
          <div
            id="observability-regressions-draft-coverage"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Draft coverage
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@regressions.draft_coverage.benchmark_drafts} draft(s)
            </p>
            <p class="text-[var(--ck-muted)] text-xs">
              {@regressions.draft_coverage.saved_eval_candidates} saved eval(s)
            </p>
          </div>
        </div>

        <%= if @regressions.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <ul class="list-disc pl-5">
              <%= for recommendation <- @regressions.recommendations do %>
                <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Recent benchmark runs
          </p>
          <%= if @regressions.benchmark_runs.recent == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No benchmark runs in the selected window.</p>
          <% else %>
            <%= for run <- @regressions.benchmark_runs.recent do %>
              <div
                id={"observability-regression-run-#{run.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      {run.suite}
                    </p>
                    <p class="text-sm font-semibold text-[var(--ck-text)]">Run #{run.id}</p>
                  </div>
                  <span class={health_pill_class(run.status)}>{run.status}</span>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">
                  Catch rate {format_rate(run.catch_rate)} · {run.caught_count}/{run.total_scenarios} scenario(s) · {run.result_count} result(s)
                </p>
                <div class="flex items-center gap-4 text-xs">
                  <p class="text-[var(--ck-muted)]">{format_datetime(run.inserted_at, "unknown")}</p>
                  <.link
                    navigate={~p"/benchmarks/runs/#{run.id}"}
                    class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
                  >
                    Open run →
                  </.link>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
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

  defp health_pill_class("red"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp health_pill_class(_status),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
end
