defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    overview = Observability.workspace_overview(opts)

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
        <div class="flex items-center justify-between gap-4 mt-6 mb-4">
          <div>
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Observability
            </p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Workspace overview</h1>
            <p class="text-[var(--ck-muted)] max-w-3xl text-[1.05rem] leading-[1.7]">
              Local-first run health, grouped problems, costs, and trace export posture.
            </p>
          </div>
          <div class="flex items-center justify-between gap-2 flex-wrap">
            <span
              id="observability-overview-health"
              class={health_pill_class(@overview.health.status)}
            >
              {@overview.health.status}
            </span>
            <span class="border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.05)] rounded-full px-3 py-[0.45rem] text-sm">
              {@overview.runs.count} recent runs
            </span>
          </div>
        </div>

        <div class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(180px,1fr))] mt-5">
          <div
            id="observability-overview-runs"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Runs
            </p>
            <strong>{@overview.runs.count} recent</strong>
            <p class="text-[var(--ck-muted)]">
              {@overview.health.red_runs} red · {@overview.health.yellow_runs} yellow · {@overview.health.green_runs} green
            </p>
          </div>

          <div
            id="observability-overview-problems"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Problems
            </p>
            <strong>{@overview.problems.count} groups</strong>
            <p class="text-[var(--ck-muted)]">
              {@overview.problems.total_findings} active finding(s)
            </p>
            <.link
              navigate={~p"/observability/problems"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Review groups
            </.link>
          </div>

          <div
            id="observability-overview-costs"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Costs
            </p>
            <strong>
              {format_currency(@overview.costs.spent_cents)} / {format_currency(
                @overview.costs.budget_cents
              )}
            </strong>
            <p class="text-[var(--ck-muted)]">
              {@overview.costs.invocations} invocation(s), {format_currency(
                @overview.costs.estimated_invocation_cents
              )} estimated
            </p>
            <.link
              navigate={~p"/observability/costs"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Review costs
            </.link>
          </div>

          <div
            id="observability-overview-telemetry"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Trace export
            </p>
            <strong>{@overview.telemetry.import_mode}</strong>
            <p class="text-[var(--ck-muted)]">
              {@overview.telemetry.export_schema_version} · {@overview.telemetry.integrity}
            </p>
            <p class="text-[var(--ck-muted)]">
              {@overview.telemetry.persisted_imports} persisted import(s)
            </p>
            <.link
              navigate={~p"/observability/imports"}
              class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
            >
              Review imports
            </.link>
          </div>
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
          id="observability-overview-recommendations"
          class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
        >
          <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
            Recommended next actions
          </p>
          <ul class="grid gap-4 m-0 p-0 list-none">
            <%= for recommendation <- @overview.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
          <.link
            navigate={~p"/observability/recommendations"}
            class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
          >
            Open recommendations
          </.link>
        </div>

        <div class="grid gap-6 grid-cols-[minmax(0,1.35fr)_minmax(280px,0.75fr)] mt-6 max-[900px]:grid-cols-1">
          <div
            id="observability-overview-run-list"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Recent session runs
            </p>
            <%= if @overview.runs.recent == [] do %>
              <p class="text-[var(--ck-muted)]">No session runs available yet.</p>
            <% else %>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for run <- @overview.runs.recent do %>
                  <li>
                    <strong>{run.title}</strong>
                    <p class="text-[var(--ck-muted)]">
                      {run.health} · {run.active_findings} active finding(s) · {run.pending_gates} gate(s)
                      <.link
                        navigate={~p"/observability/sessions/#{run.id}"}
                        class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
                      >
                        Open run
                      </.link>
                      <.link
                        href={~p"/observability/sessions/#{run.id}/export.json"}
                        class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]"
                      >
                        Export
                      </.link>
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div
            id="observability-overview-problem-list"
            class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          >
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)]">
              Top problems
            </p>
            <%= if @overview.problems.top == [] do %>
              <p class="text-[var(--ck-muted)]">No active problems detected.</p>
            <% else %>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for problem <- @overview.problems.top do %>
                  <li>
                    <strong>{problem.rule_id}</strong>
                    <p class="text-[var(--ck-muted)]">
                      {problem.health} · {problem.count} finding(s) · {problem.affected_session_count} session(s)
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"),
    do:
      "border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-sm bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp health_pill_class("yellow"),
    do:
      "border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-sm bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp health_pill_class(_),
    do:
      "border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
