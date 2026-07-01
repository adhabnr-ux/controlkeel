defmodule ControlKeelWeb.ObservabilityEvalsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    eval_candidates = Observability.eval_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Eval Candidates")
     |> assign(:eval_candidates, eval_candidates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/evals">
      <section
        id="observability-evals-page"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Eval candidates</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Advisory regression candidates derived from grouped problems and feedback evidence.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0 flex-wrap justify-end">
            <span id="observability-evals-health" class={health_pill_class(@eval_candidates.health)}>
              {@eval_candidates.health}
            </span>
            <span class={neutral_pill_class()}>{@eval_candidates.count} candidate(s)</span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs evals" />

        <%= if @eval_candidates.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommended next actions
            </p>
            <ul class="list-disc pl-5">
              <%= for recommendation <- @eval_candidates.recommendations do %>
                <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <div id="observability-evals-list" class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Active candidates
          </p>
          <%= if @eval_candidates.candidates == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No eval candidates are currently active.</p>
          <% else %>
            <%= for candidate <- @eval_candidates.candidates do %>
              <div
                id={"observability-eval-#{candidate.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      {candidate.category}
                    </p>
                    <p class="text-sm font-semibold text-[var(--ck-text)]">{candidate.title}</p>
                  </div>
                  <span class={priority_pill_class(candidate.priority)}>{candidate.priority}</span>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">
                  {candidate.rule_id} · {candidate.finding_count} finding(s) · {candidate.affected_session_count} session(s)
                </p>
                <p class="text-sm text-[var(--ck-text)] leading-relaxed">
                  {candidate.evidence_summary}
                </p>
                <p class="text-[var(--ck-muted)] text-xs">
                  Benchmark hint: {candidate.benchmark_hint}
                </p>
                <p class="text-[var(--ck-muted)] text-xs">
                  Human gate required: {candidate.human_gate_required}
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp health_pill_class("red"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp health_pill_class("yellow"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp health_pill_class(_),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp priority_pill_class("critical"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp priority_pill_class("high"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp priority_pill_class(_),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,255,255,0.04)] text-[var(--ck-text)]"

end
