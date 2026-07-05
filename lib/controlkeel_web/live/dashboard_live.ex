defmodule ControlKeelWeb.DashboardLive do
  use ControlKeelWeb, :live_view

  import ControlKeelWeb.ProviderStatusComponents

  alias ControlKeel.ACPRegistry
  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker
  alias ControlKeel.RuntimeMode

  @impl true
  def mount(_params, _session, socket) do
    project_root = endpoint_config(socket, :project_root) || File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(
       benchmark_summary: Benchmark.benchmark_summary(),
       provider_status: ProviderBroker.status(project_root),
       recent_sessions: Mission.list_recent_sessions(4),
       registry_status: ACPRegistry.status(),
       ship_summary: Analytics.funnel_summary(),
       runtime_mode: RuntimeMode.current()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <% catch_rate = @benchmark_summary.average_catch_rate
      overhead = @benchmark_summary.average_overhead_percent
      proof_coverage = @ship_summary.outcome_metrics.proof_backed_task_coverage_percent
      deploy_ready = @ship_summary.outcome_metrics.deploy_ready_task_rate_percent
      avg_findings = @ship_summary.average_findings_per_session %>

      <section class="mx-auto flex max-w-7xl flex-col gap-6">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-lime-300">Dashboard</p>
            <h1 class="mt-2 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
              Agent Control Plane
            </h1>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-zinc-400">
              Live mission state, findings, proof coverage, benchmark signal, and ship readiness in one operator view.
            </p>
          </div>
          <a
            href={~p"/missions/start"}
            class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-4 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
          >
            <.icon name="hero-plus" class="size-4" /> New Mission
          </a>
        </div>

        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <article class="rounded-2xl border border-white/10 bg-white/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-medium text-zinc-400">Benchmark Catch Rate</p>
              <span class="rounded-full bg-lime-300/10 p-2 text-lime-300">
                <.icon name="hero-shield-check" class="size-4" />
              </span>
            </div>
            <p class="mt-4 text-3xl font-semibold text-white">{format_percent(catch_rate)}</p>
            <div class="mt-5 h-2 overflow-hidden rounded-full bg-white/10">
              <div
                class="h-full rounded-full bg-lime-300"
                style={"width: #{min(catch_rate || 0, 100)}%"}
              />
            </div>
            <p class="mt-3 text-xs text-zinc-500">
              {@benchmark_summary.total_runs} runs across {@benchmark_summary.total_suites} suites
            </p>
          </article>

          <article class="rounded-2xl border border-white/10 bg-white/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-medium text-zinc-400">Proof Coverage</p>
              <span class="rounded-full bg-sky-400/10 p-2 text-sky-300">
                <.icon name="hero-document-check" class="size-4" />
              </span>
            </div>
            <p class="mt-4 text-3xl font-semibold text-white">{format_percent(proof_coverage)}</p>
            <div class="mt-5 h-2 overflow-hidden rounded-full bg-white/10">
              <div
                class="h-full rounded-full bg-sky-300"
                style={"width: #{min(proof_coverage || 0, 100)}%"}
              />
            </div>
            <p class="mt-3 text-xs text-zinc-500">Done tasks with attached evidence</p>
          </article>

          <article class="rounded-2xl border border-white/10 bg-white/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-medium text-zinc-400">Deploy Ready Rate</p>
              <span class="rounded-full bg-emerald-400/10 p-2 text-emerald-300">
                <.icon name="hero-rocket-launch" class="size-4" />
              </span>
            </div>
            <p class="mt-4 text-3xl font-semibold text-white">{format_percent(deploy_ready)}</p>
            <div class="mt-5 h-2 overflow-hidden rounded-full bg-white/10">
              <div
                class="h-full rounded-full bg-emerald-300"
                style={"width: #{min(deploy_ready || 0, 100)}%"}
              />
            </div>
            <p class="mt-3 text-xs text-zinc-500">Release-ready task outcomes</p>
          </article>

          <article class="rounded-2xl border border-white/10 bg-white/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
            <div class="flex items-center justify-between gap-3">
              <p class="text-sm font-medium text-zinc-400">Finding Density</p>
              <span class="rounded-full bg-amber-300/10 p-2 text-amber-200">
                <.icon name="hero-exclamation-triangle" class="size-4" />
              </span>
            </div>
            <p class="mt-4 text-3xl font-semibold text-white">{format_number(avg_findings)}</p>

            <p class="mt-3 text-xs text-zinc-500">Average findings per recent mission</p>
          </article>
        </div>

        <aside class="grid gap-6 grid-cols-2 w-full">
          <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
            <div class="flex items-center justify-between gap-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
                  Funnel
                </p>
                <h2 class="mt-1 text-xl font-semibold text-white">Delivery Flow</h2>
              </div>
              <span class="rounded-full border border-white/10 px-3 py-1 text-xs text-zinc-400">
                {@ship_summary.recent_session_count} sessions
              </span>
            </div>
            <div class="mt-5 space-y-4">
              <%= for step <- @ship_summary.steps do %>
                <div>
                  <div class="flex items-center justify-between gap-3 text-sm">
                    <span class="capitalize text-zinc-300">
                      {String.replace(step.step, "_", " ")}
                    </span>
                    <span class="font-semibold text-white">{step.count}</span>
                  </div>
                  <div class="mt-2 h-2 overflow-hidden rounded-full bg-white/10">
                    <div
                      class="h-full rounded-full bg-lime-300"
                      style={"width: #{min(step.conversion_percent || 0, 100)}%"}
                    />
                  </div>
                </div>
              <% end %>
            </div>
          </section>

          <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
                  Telemetry
                </p>
                <h2 class="mt-1 text-xl font-semibold text-white">Signal Preview</h2>
              </div>
              <a
                href={~p"/benchmarks"}
                class="text-sm font-medium text-zinc-400 hover:text-lime-300"
              >
                Benchmarks
              </a>
            </div>

            <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div class="rounded-2xl bg-white/[0.04] p-3">
                <dt class="text-zinc-500">Avg overhead</dt>
                <dd class="mt-1 font-semibold text-white">{format_percent(overhead)}</dd>
              </div>
              <div class="rounded-2xl bg-white/[0.04] p-3">
                <dt class="text-zinc-500">First finding</dt>
                <dd class="mt-1 font-semibold text-white">
                  {if @ship_summary.average_time_to_first_finding_seconds,
                    do: "#{format_number(@ship_summary.average_time_to_first_finding_seconds)}s",
                    else: "Not recorded"}
                </dd>
              </div>
            </dl>
          </section>
        </aside>

        <.current_status provider_status={@provider_status} />

        <.provider_bootstrap_detail provider_status={@provider_status} />

        <.registry_cache registry_status={@registry_status} />

        <div class="grid gap-6 w-full ">
          <section class="rounded-3xl border border-white/10 bg-zinc-900/70 shadow-2xl shadow-black/20 backdrop-blur">
            <div class="flex items-center justify-between border-b border-white/10 p-5">
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
                Recent Missions
              </p>
              <a
                href={~p"/missions"}
                class="inline-flex items-center gap-2 text-sm font-medium text-zinc-300 transition hover:text-lime-300"
              >
                View all missions <.icon name="hero-arrow-up-right" class="size-4" />
              </a>
            </div>

            <div class="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-4">
              <%= if @recent_sessions == [] do %>
                <div class="rounded-2xl border border-white/10 bg-white/[0.03] p-6 md:col-span-2 xl:col-span-4">
                  <p class="text-base font-medium text-white">No missions yet.</p>
                  <p class="mt-1 text-sm text-zinc-500">
                    Start a mission to populate live governance telemetry.
                  </p>
                </div>
              <% else %>
                <%= for session <- @recent_sessions do %>
                  <a
                    href={~p"/missions/#{session.id}"}
                    class="rounded-2xl border border-white/10 bg-white/[0.03] p-4 transition hover:border-lime-300/40 hover:bg-white/[0.05]"
                  >
                    <div class="flex items-start justify-between gap-3">
                      <p class="line-clamp-2 text-sm font-semibold text-white">{session.title}</p>
                      <span class={[
                        "inline-flex rounded-full px-2 py-1 text-[10px] font-semibold capitalize ring-1",
                        session.risk_tier in ["critical", "high"] &&
                          "bg-red-400/10 text-red-200 ring-red-300/20",
                        session.risk_tier in ["medium", "moderate"] &&
                          "bg-amber-300/10 text-amber-100 ring-amber-200/20",
                        session.risk_tier in ["low"] &&
                          "bg-emerald-300/10 text-emerald-100 ring-emerald-200/20",
                        session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-white/10 text-zinc-300 ring-white/15"
                      ]}>
                        {session.risk_tier}
                      </span>
                    </div>
                    <p class="mt-2 line-clamp-3 text-xs leading-5 text-zinc-500">
                      {session.objective}
                    </p>
                    <div class="mt-4 flex items-center justify-between text-xs text-zinc-400">
                      <span>{Enum.count(session.tasks)} tasks</span>
                      <span>{Enum.count(session.findings)} findings</span>
                    </div>
                  </a>
                <% end %>
              <% end %>
            </div>
          </section>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_percent(value), do: "#{value}%"

  defp format_number(nil), do: "Not recorded"
  defp format_number(value) when is_float(value), do: Float.round(value, 1)
  defp format_number(value), do: value

  defp endpoint_config(socket, key) do
    socket.endpoint.config(key)
  end
end
