defmodule ControlKeelWeb.ObservabilityLoopLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    loop = Observability.loop_status(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Learning Loop")
     |> assign(:loop, loop)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-loop"
      class="border border-border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-primary">Learning loop</h1>
          <p class="text-muted-foreground text-sm mt-1">
            Read-only, local-first status for turning repeated CK and agent use into reviewed evals, benchmark evidence, and human-gated improvement candidates.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <span class={health_pill_class(@loop.health)}>{@loop.health}</span>
          <span class="inline-flex items-center border border-border rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
            {@loop.learning_loop.mode}
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs loop" />

      <div class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
        <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
          Safety boundary
        </p>
        <p class="text-sm font-semibold text-foreground">
          Read-only: {@loop.read_only} · Mutation: {@loop.mutation}
        </p>
        <p class="text-muted-foreground text-xs">
          Automatic benchmark execution: {@loop.learning_loop.automatic_benchmark_execution} · Automatic promotion: {@loop.learning_loop.automatic_promotion}
        </p>
        <p class="text-muted-foreground text-xs">
          Generated benchmarks are {@loop.learning_loop.generated_benchmarks}.
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Problems
          </p>
          <p class="text-lg font-semibold text-foreground">
            {@loop.active_problems.count} group(s)
          </p>
          <p class="text-muted-foreground text-xs">
            {@loop.active_problems.total_findings} active finding(s)
          </p>
        </div>
        <div class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Evals</p>
          <p class="text-lg font-semibold text-foreground">
            {@loop.evals.derived} derived / {@loop.evals.saved} saved
          </p>
          <p class="text-muted-foreground text-xs">
            Saved status: {format_frequency(@loop.evals.saved_by_status)}
          </p>
        </div>
        <div class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Benchmarks
          </p>
          <p class="text-lg font-semibold text-foreground">
            {@loop.benchmarks.scenarios} scenario(s)
          </p>
          <p class="text-muted-foreground text-xs">
            {@loop.benchmarks.drafts} draft(s), readiness {@loop.benchmarks.history_readiness.status}
          </p>
        </div>
        <div class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Promotions
          </p>
          <p class="text-lg font-semibold text-foreground">
            {@loop.promotions.count} candidate(s)
          </p>
          <p class="text-muted-foreground text-xs">
            Readiness: {format_frequency(@loop.promotions.by_readiness)}
          </p>
        </div>
      </div>

      <div class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Blockers
        </p>
        <%= if @loop.blockers == [] do %>
          <p class="text-muted-foreground text-sm">No learning-loop blockers detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for blocker <- @loop.blockers do %>
              <div class="rounded-xl px-4 py-3 border border-border bg-[rgba(255,255,255,0.015)]">
                <p class="text-sm font-semibold text-foreground">{blocker.id}</p>
                <p class="text-muted-foreground text-xs">{blocker.reason}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Next actions
        </p>
        <%= if @loop.next_actions == [] do %>
          <p class="text-muted-foreground text-sm">No next actions.</p>
        <% else %>
          <div class="space-y-2">
            <%= for action <- @loop.next_actions do %>
              <div class="rounded-xl px-4 py-3 border border-border bg-[rgba(255,255,255,0.015)] space-y-1">
                <p class="text-sm font-semibold text-foreground">
                  [{action.priority}] {action.title}
                </p>
                <p class="text-muted-foreground text-xs">{action.suggested_action}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @loop.recommendations != [] do %>
        <div class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="space-y-2 list-disc pl-5">
            <%= for recommendation <- @loop.recommendations do %>
              <li class="text-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </section>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center border border-border rounded-full px-3 py-1.5 text-sm bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center border border-border rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp health_pill_class(_),
    do:
      "inline-flex items-center border border-border rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
