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
    <section id="observability-loop" class="w-full space-y-8">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Learning loop
          </h1>
          <p class="text-sm text-muted-foreground">
            Read-only, local-first status for turning repeated CK and agent use into reviewed evals, benchmark evidence, and human-gated improvement candidates.
          </p>
        </div>

        <div class="flex items-center gap-3 shrink-0">
          <span class={health_pill_class(@loop.health)}>{@loop.health}</span>
          <span class="rounded-full bg-primary/10 px-3 py-1.5 text-sm font-semibold text-primary ring-1 ring-primary/20">
            {@loop.learning_loop.mode}
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs loop" />

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
        <.section_title>Safety boundary</.section_title>
        <p class="text-sm font-medium text-foreground">
          Read-only: {@loop.read_only} · Mutation: {@loop.mutation}
        </p>
        <p class="text-xs text-muted-foreground">
          Automatic benchmark execution: {@loop.learning_loop.automatic_benchmark_execution} · Automatic promotion: {@loop.learning_loop.automatic_promotion}
        </p>
        <p class="text-xs text-muted-foreground">
          Generated benchmarks are {@loop.learning_loop.generated_benchmarks}.
        </p>
      </section>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Problems</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.active_problems.count} group(s)
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@loop.active_problems.total_findings} active finding(s)
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Evals</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.evals.derived} derived / {@loop.evals.saved} saved
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            Saved status: {format_frequency(@loop.evals.saved_by_status)}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Benchmarks</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.benchmarks.scenarios} scenario(s)
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            {@loop.benchmarks.drafts} draft(s), readiness {@loop.benchmarks.history_readiness.status}
          </p>
        </article>

        <article class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm font-medium text-muted-foreground">Promotions</p>
          <p class="mt-2 text-xl font-semibold text-foreground/90">
            {@loop.promotions.count} candidate(s)
          </p>
          <p class="mt-1 text-xs text-muted-foreground">
            Readiness: {format_frequency(@loop.promotions.by_readiness)}
          </p>
        </article>
      </div>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Blockers</.section_title>
        <%= if @loop.blockers == [] do %>
          <p class="text-sm text-muted-foreground">No learning-loop blockers detected.</p>
        <% else %>
          <div class="space-y-2">
            <%= for blocker <- @loop.blockers do %>
              <div class="flex items-start justify-between gap-3 rounded-lg px-3 py-2 bg-destructive/10">
                <p class="text-sm font-medium text-foreground">{blocker.id}</p>
                <p class="shrink-0 text-xs text-muted-foreground">{blocker.reason}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
        <.section_title>Next actions</.section_title>
        <%= if @loop.next_actions == [] do %>
          <p class="text-sm text-muted-foreground">No next actions.</p>
        <% else %>
          <div class="space-y-2">
            <%= for action <- @loop.next_actions do %>
              <div class="rounded-lg px-3 py-2 bg-muted/30 space-y-1">
                <p class="text-sm font-medium text-foreground">
                  [{action.priority}] {action.title}
                </p>
                <p class="text-xs text-muted-foreground">{action.suggested_action}</p>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>

      <%= if @loop.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
          <.section_title>Recommendations</.section_title>
          <ul class="space-y-2 text-sm leading-relaxed text-muted-foreground list-disc ml-5">
            <%= for recommendation <- @loop.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </section>
      <% end %>
    </section>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp health_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-3 py-1.5 text-sm font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
