defmodule ControlKeelWeb.ObservabilityOverviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill
  alias ControlKeelWeb.RecentSessions

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    overview = Observability.workspace_overview([limit: 6] ++ opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability")
     |> assign(:overview, overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-overview-page"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-primary">Observability</h1>
          <p class="text-muted-foreground text-sm mt-1">
            Session runs, problems, costs, and trace export at a glance.
          </p>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs" />

      <div class="grid grid-cols-2 md:grid-cols-2 gap-4">
        <div
          id="observability-overview-runs"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Runs</p>
          <p class="text-xl font-semibold">{@overview.runs.count} recent</p>
          <p class="text-muted-foreground text-xs">
            {@overview.health.red_runs} red · {@overview.health.yellow_runs} yellow · {@overview.health.green_runs} green
          </p>
        </div>

        <div
          id="observability-overview-problems"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Problems
          </p>
          <p class="text-xl font-semibold">
            {@overview.problems.count} groups
          </p>
          <p class="text-muted-foreground text-xs">
            {@overview.problems.total_findings} active finding(s)
          </p>
          <.link
            navigate={~p"/observability/problems"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Review groups
          </.link>
        </div>

        <div
          id="observability-overview-costs"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Costs</p>
          <p class="text-xl font-semibold">
            {format_currency(@overview.costs.spent_cents)} / {format_currency(
              @overview.costs.budget_cents
            )}
          </p>
          <p class="text-muted-foreground text-xs">
            {@overview.costs.invocations} invocation(s), {format_currency(
              @overview.costs.estimated_invocation_cents
            )} estimated
          </p>
          <.link
            navigate={~p"/observability/costs"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Review costs
          </.link>
        </div>

        <div
          id="observability-overview-telemetry"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Trace export
          </p>
          <p class="text-xl font-semibold">
            {@overview.telemetry.import_mode}
          </p>
          <p class="text-muted-foreground text-xs">
            {@overview.telemetry.export_schema_version} · {@overview.telemetry.integrity}
          </p>
          <p class="text-muted-foreground text-xs">
            {@overview.telemetry.persisted_imports} persisted import(s)
          </p>
          <.link
            navigate={~p"/observability/imports"}
            class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
          >
            Review imports
          </.link>
        </div>
      </div>

      <div class="space-y-2">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Recommended next actions
        </p>
        <%= if @overview.recommendations == [] do %>
          <p class="text-muted-foreground text-sm">No recommendations available.</p>
        <% else %>
          <ul class="space-y-1 list-disc pl-5">
            <%= for recommendation <- @overview.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        <% end %>
        <.link
          navigate={~p"/observability/recommendations"}
          class="text-sm text-primary font-semibold hover:opacity-80 transition-opacity"
        >
          Open recommendations →
        </.link>
      </div>

      <div class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Top problems
        </p>
        <%= if @overview.problems.top == [] do %>
          <p class="text-muted-foreground text-sm">No active problems detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for problem <- @overview.problems.top do %>
              <div class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)]">
                <p class="text-sm font-medium">{problem.rule_id}</p>
                <p class="text-muted-foreground text-xs mt-1">
                  {problem.health} · {problem.count} finding(s) · {problem.affected_session_count} session(s)
                </p>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <RecentSessions.session_observability_section runs={@overview.runs.recent} />
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
