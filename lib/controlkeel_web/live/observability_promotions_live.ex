defmodule ControlKeelWeb.ObservabilityPromotionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    promotions = Observability.promotion_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Promotion Candidates")
     |> assign(:promotions, promotions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/promotions">
      <section
        id="observability-promotions"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Promotion candidates</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Advisory, human-gated promotion candidates backed by local observability evidence.
            </p>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@promotions.count} candidate(s)
            </span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs promotions" />

        <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
            Execution boundary
          </p>
          <p class="text-sm font-semibold text-[var(--ck-text)]">
            Promotion execution: {@promotions.promotion_execution}
          </p>
          <p class="text-[var(--ck-muted)] text-xs">
            This page does not mutate policy, router, prompt, or autofix artifacts.
          </p>
        </div>

        <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
            Recommendations
          </p>

          <%= if @promotions.recommendations == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No promotion recommendations yet.</p>
          <% else %>
            <ul class="space-y-2 list-disc pl-4">
              <%= for recommendation <- @promotions.recommendations do %>
                <li class="text-[var(--ck-text)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Candidates
          </p>

          <%= if @promotions.candidates == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No promotion candidates yet.</p>
          <% else %>
            <%= for candidate <- @promotions.candidates do %>
              <div
                id={"observability-promotion-candidate-#{candidate.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
              >
                <div class="flex items-center justify-between gap-4">
                  <p class="text-sm font-semibold text-[var(--ck-text)]">{candidate.rule_id}</p>
                  <span class={readiness_pill_class(candidate.readiness)}>{candidate.readiness}</span>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">{candidate.suggested_action}</p>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp readiness_pill_class("ready"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp readiness_pill_class("needs_draft"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp readiness_pill_class(_),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(255,255,255,0.06)] text-[var(--ck-muted)]"
end
