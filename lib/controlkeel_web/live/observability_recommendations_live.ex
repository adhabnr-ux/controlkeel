defmodule ControlKeelWeb.ObservabilityRecommendationsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    recommendations = Observability.recommendations(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Recommendations")
     |> assign(:recommendations, recommendations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section
        id="observability-recommendations"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-6">
              Recommendations
            </p>
            <h1 class="text-xl font-semibold text-[var(--ck-text)]">Recommendations</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Prioritized local next actions from runs, problems, costs, and proof signals.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class={health_pill_class(@recommendations.health)}>
              {@recommendations.health}
            </span>
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@recommendations.count} action(s)
            </span>
            <.link
              navigate={~p"/observability/evals"}
              class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
            >
              Eval candidates →
            </.link>
            <.link
              navigate={~p"/observability"}
              class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
            >
              Overview →
            </.link>
          </div>
        </div>

        <div class="text-[var(--ck-muted)] text-xs font-mono border border-[var(--ck-stroke)] rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
          controlkeel obs recommend
        </div>

        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Actions</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@recommendations.count}</p>
            <p class="text-[var(--ck-muted)] text-xs">Prioritized by current local evidence</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Categories</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {length(@recommendations.categories)}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">
              {Enum.join(@recommendations.categories, ", ")}
            </p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Workspace</p>
            <p class="text-lg font-semibold text-[var(--ck-text)] truncate">
              {@recommendations.workspace.name}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">Local-first summary</p>
          </div>
        </div>

        <div class="space-y-3">
          <%= if @recommendations.actions == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No recommendations are currently active.</p>
          <% else %>
            <%= for action <- @recommendations.actions do %>
              <div
                id={"observability-recommendation-#{action.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="space-y-1 min-w-0">
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      {action.category}
                    </p>
                    <p class="text-sm font-semibold text-[var(--ck-text)]">{action.title}</p>
                  </div>
                  <span class={priority_pill_class(action.priority)}>{action.priority}</span>
                </div>
                <p class="text-[var(--ck-muted)] text-xs">{action.evidence}</p>
                <p class="text-[var(--ck-text)] text-sm">{action.suggested_action}</p>
                <div class="flex items-center gap-4 text-xs text-[var(--ck-muted)]">
                  <span>Source: {action.source}</span>
                  <span>Human gate: {action.human_gate_required}</span>
                  <.link
                    navigate={action.link}
                    class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
                  >
                    Open related view →
                  </.link>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </Layouts.app>
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
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(255,107,107,0.1)] text-[#ff6b6b]"

  defp priority_pill_class("high"),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(255,207,107,0.1)] text-[#ffcf6b]"

  defp priority_pill_class(_),
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(255,255,255,0.06)] text-[var(--ck-muted)]"
end
