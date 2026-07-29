defmodule ControlKeelWeb.DashboardLive do
  use ControlKeelWeb, :live_view

  import ControlKeelWeb.ProviderStatusComponents

  alias ControlKeel.Agent.ACPRegistry
  alias ControlKeel.Analytics
  alias ControlKeel.Benchmark
  alias ControlKeel.Mission
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    project_root = ControlKeelWeb.Endpoint.config(:project_root) || File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(
       benchmark_summary: Benchmark.benchmark_summary(),
       provider_status: ProviderBroker.status(project_root),
       recent_sessions: Mission.list_recent_sessions(4),
       registry_status: ACPRegistry.status(),
       ship_summary: Analytics.funnel_summary(),
       runtime_mode: Mode.current()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <% catch_rate = @benchmark_summary.average_catch_rate
    overhead = @benchmark_summary.average_overhead_percent
    proof_coverage = @ship_summary.outcome_metrics.proof_backed_task_coverage_percent
    deploy_ready = @ship_summary.outcome_metrics.deploy_ready_task_rate_percent
    avg_findings = @ship_summary.average_findings_per_session %>

    <section class="mx-auto flex max-w-7xl flex-col gap-6">
      <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">Dashboard</p>
          <h1 class="mt-2 text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            Agent Control Plane
          </h1>
          <p class="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
            Live mission state, findings, proof coverage, benchmark signal, and ship readiness in one operator view.
          </p>
        </div>
        <a
          href={~p"/missions/start"}
          class="inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
        >
          <.icon name="hero-plus" class="size-4" /> New Mission
        </a>
      </div>

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-muted/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Benchmark Catch Rate</p>
            <span class="rounded-full bg-primary/10 p-2 text-primary">
              <.icon name="hero-shield-check" class="size-4" />
            </span>
          </div>
          <p class="mt-4 text-3xl font-semibold text-foreground">{format_percent(catch_rate)}</p>
          <div class="mt-5 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-primary"
              style={"width: #{min(catch_rate || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">
            {@benchmark_summary.total_runs} runs across {@benchmark_summary.total_suites} suites
          </p>
        </article>

        <article class="rounded-2xl border bg-muted/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Proof Coverage</p>
            <span class="rounded-full bg-info/10 p-2 text-info">
              <.icon name="hero-document-check" class="size-4" />
            </span>
          </div>
          <p class="mt-4 text-3xl font-semibold text-foreground">{format_percent(proof_coverage)}</p>
          <div class="mt-5 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-info"
              style={"width: #{min(proof_coverage || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Done tasks with attached evidence</p>
        </article>

        <article class="rounded-2xl border bg-muted/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Deploy Ready Rate</p>
            <span class="rounded-full bg-[var(--ck-success)]/10 p-2 text-[var(--ck-success)]">
              <.icon name="hero-rocket-launch" class="size-4" />
            </span>
          </div>
          <p class="mt-4 text-3xl font-semibold text-foreground">{format_percent(deploy_ready)}</p>
          <div class="mt-5 h-2 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-[var(--ck-success)]"
              style={"width: #{min(deploy_ready || 0, 100)}%"}
            />
          </div>
          <p class="mt-3 text-xs text-muted-foreground">Release-ready task outcomes</p>
        </article>

        <article class="rounded-2xl border bg-muted/[0.06] p-5 shadow-xl shadow-black/10 backdrop-blur">
          <div class="flex items-center justify-between gap-3">
            <p class="text-sm font-medium text-muted-foreground">Finding Density</p>
            <span class="rounded-full bg-[var(--ck-warning)]/10 p-2 text-[var(--ck-warning)]">
              <.icon name="hero-exclamation-triangle" class="size-4" />
            </span>
          </div>
          <p class="mt-4 text-3xl font-semibold text-foreground">{format_number(avg_findings)}</p>

          <p class="mt-3 text-xs text-muted-foreground">Average findings per recent mission</p>
        </article>
      </div>

      <aside class="grid gap-6 grid-cols-2 w-full">
        <section class="rounded-3xl border bg-card/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
                Funnel
              </p>
              <h2 class="mt-1 text-xl font-semibold text-foreground">Delivery Flow</h2>
            </div>
            <span class="rounded-full border px-3 py-1 text-xs text-muted-foreground">
              {@ship_summary.recent_session_count} sessions
            </span>
          </div>
          <div class="mt-5 space-y-4">
            <%= for step <- @ship_summary.steps do %>
              <div>
                <div class="flex items-center justify-between gap-3 text-sm">
                  <span class="capitalize text-muted-foreground">
                    {String.replace(step.step, "_", " ")}
                  </span>
                  <span class="font-semibold text-foreground">{step.count}</span>
                </div>
                <div class="mt-2 h-2 overflow-hidden rounded-full bg-muted">
                  <div
                    class="h-full rounded-full bg-primary"
                    style={"width: #{min(step.conversion_percent || 0, 100)}%"}
                  />
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <section class="rounded-3xl border bg-card/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
                Telemetry
              </p>
              <h2 class="mt-1 text-xl font-semibold text-foreground">Signal Preview</h2>
            </div>
            <a
              href={~p"/benchmarks"}
              class="text-sm font-medium text-muted-foreground hover:text-primary"
            >
              Benchmarks
            </a>
          </div>

          <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
            <div class="rounded-2xl bg-muted/[0.04] p-3">
              <dt class="text-muted-foreground">Avg overhead</dt>
              <dd class="mt-1 font-semibold text-foreground">{format_percent(overhead)}</dd>
            </div>
            <div class="rounded-2xl bg-muted/[0.04] p-3">
              <dt class="text-muted-foreground">First finding</dt>
              <dd class="mt-1 font-semibold text-foreground">
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
        <section class="rounded-3xl border bg-card/70 shadow-2xl shadow-black/20 backdrop-blur">
          <div class="flex items-center justify-between border-b p-5">
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
              Recent Missions
            </p>
            <a
              href={~p"/missions"}
              class="inline-flex items-center gap-2 text-sm font-medium text-muted-foreground transition hover:text-primary"
            >
              View all missions <.icon name="hero-arrow-up-right" class="size-4" />
            </a>
          </div>

          <div class="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-4">
            <%= if @recent_sessions == [] do %>
              <div class="rounded-2xl border bg-muted/[0.03] p-6 md:col-span-2 xl:col-span-4">
                <p class="text-base font-medium text-foreground">No missions yet.</p>
                <p class="mt-1 text-sm text-muted-foreground">
                  Start a mission to populate live governance telemetry.
                </p>
              </div>
            <% else %>
              <%= for session <- @recent_sessions do %>
                <a
                  href={~p"/missions/#{session.id}"}
                  class="rounded-2xl border bg-muted/[0.03] p-4 transition hover:border-primary/40 hover:bg-muted/[0.05]"
                >
                  <div class="flex items-start justify-between gap-3">
                    <p class="line-clamp-2 text-sm font-semibold text-foreground">{session.title}</p>
                    <span class={[
                      "inline-flex rounded-full px-2 py-1 text-[10px] font-semibold capitalize ring-1",
                      session.risk_tier in ["critical", "high"] &&
                        "bg-destructive/10 text-destructive ring-destructive/20",
                      session.risk_tier in ["medium", "moderate"] &&
                        "bg-[var(--ck-warning)]/10 text-[var(--ck-warning)] ring-[var(--ck-warning)]/20",
                      session.risk_tier in ["low"] &&
                        "bg-[var(--ck-success)]/10 text-[var(--ck-success)] ring-[var(--ck-success)]/20",
                      session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                        "bg-muted text-muted-foreground ring-border"
                    ]}>
                      {session.risk_tier}
                    </span>
                  </div>
                  <p class="mt-2 line-clamp-3 text-xs leading-5 text-muted-foreground">
                    {session.objective}
                  </p>
                  <div class="mt-4 flex items-center justify-between text-xs text-muted-foreground">
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
    """
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_percent(value), do: "#{value}%"

  defp format_number(nil), do: "Not recorded"
  defp format_number(value) when is_float(value), do: Float.round(value, 1)
  defp format_number(value), do: value
end
