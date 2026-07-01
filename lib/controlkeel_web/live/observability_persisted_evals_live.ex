defmodule ControlKeelWeb.ObservabilityPersistedEvalsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    saved = Observability.saved_eval_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Saved Eval Candidates")
     |> assign(:saved, saved)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/evals/persisted">
      <section
        id="observability-persisted-evals-page"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Saved eval candidates</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Local, human-gated candidate records saved from grouped problem feedback loops.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span id="observability-persisted-evals-count" class={neutral_pill_class()}>
              {@saved.count} saved
            </span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs evals persisted" />

        <div class="grid grid-cols-2 gap-4">
          <div
            id="observability-persisted-evals-status"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Status</p>
            <p class="text-lg font-semibold text-[var(--ck-text)]">
              {format_frequency(@saved.by_status)}
            </p>
          </div>
          <div
            id="observability-persisted-evals-priority"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Priority</p>
            <p class="text-lg font-semibold text-[var(--ck-text)]">
              {format_frequency(@saved.by_priority)}
            </p>
          </div>
        </div>

        <%= if @saved.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <ul class="list-disc pl-5">
              <%= for recommendation <- @saved.recommendations do %>
                <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <div id="observability-persisted-evals-list" class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Saved candidates
          </p>
          <%= if @saved.candidates == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No saved eval candidates yet.</p>
          <% else %>
            <%= for candidate <- @saved.candidates do %>
              <div
                id={"observability-persisted-eval-#{candidate.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      {candidate.category || "uncategorized"}
                    </p>
                    <p class="text-sm font-semibold text-[var(--ck-text)]">{candidate.title}</p>
                  </div>
                  <span class={neutral_pill_class()}>{candidate.status}</span>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">
                  {candidate.rule_id} · {candidate.priority} · human gate {candidate.human_gate_required}
                </p>
                <p class="text-sm text-[var(--ck-text)] leading-relaxed">
                  {candidate.evidence_summary}
                </p>
                <p class="text-[var(--ck-muted)] text-xs">Next: {candidate.suggested_action}</p>
                <p class="text-[var(--ck-muted)] text-xs">
                  Benchmark hint: {candidate.benchmark_hint || "none"}
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp neutral_pill_class,
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,255,255,0.04)] text-[var(--ck-text)]"
end
