defmodule ControlKeelWeb.ObservabilitySessionLayout do
  use ControlKeelWeb, :html

  @doc """
  Renders the session-scoped observability layout with Overview / Timeline /
  Memory / Export JSON tabs. Shared by the three `/observability/sessions/:id`
  routes so the tab bar stays consistent and highlights the active view.
  """
  attr :flash, :map, required: true
  attr :current_path, :string, default: ""
  attr :session_id, :integer, required: true
  attr :session_title, :string, default: ""
  slot :inner_block, required: true

  def session(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16">
        <div class="space-y-1 mb-4">
          <.link
            navigate={~p"/observability"}
            class="text-sm text-[var(--ck-muted)] hover:text-[var(--ck-lime)] transition-colors"
          >
            ← Observability
          </.link>
          <h2 class="text-xl font-semibold text-[var(--ck-text)] leading-6 mt-4">
            {@session_title}
          </h2>
          <p class="text-[var(--ck-muted)] text-sm">Session run observability</p>
        </div>

        <div class="flex gap-3 flex-wrap mb-8">
          <.link
            navigate={~p"/observability/sessions/#{@session_id}"}
            class={tab_class("/observability/sessions/#{@session_id}", @current_path)}
          >
            Overview
          </.link>
          <.link
            id="observability-open-timeline"
            navigate={~p"/observability/sessions/#{@session_id}/timeline"}
            class={tab_class("/observability/sessions/#{@session_id}/timeline", @current_path)}
          >
            Timeline
          </.link>
          <.link
            id="observability-open-memory"
            navigate={~p"/observability/sessions/#{@session_id}/memory"}
            class={tab_class("/observability/sessions/#{@session_id}/memory", @current_path)}
          >
            Memory
          </.link>
          <.link
            id="observability-export-json"
            href={~p"/observability/sessions/#{@session_id}/export.json"}
            class={tab_inactive_class()}
          >
            Export JSON
          </.link>
        </div>

        {render_slot(@inner_block)}
      </section>
    </DashboardLayout.dashboard>
    """
  end

  defp tab_class(path, current_path) do
    if path == current_path do
      "#{tab_base_class()} text-[var(--ck-lime)] bg-[rgba(190,242,100,0.1)] border-[var(--ck-lime)]"
    else
      tab_inactive_class()
    end
  end

  defp tab_inactive_class do
    "#{tab_base_class()} text-[var(--ck-text)] hover:text-[var(--ck-lime)] bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] border-[var(--ck-stroke)]"
  end

  defp tab_base_class do
    "text-sm font-medium transition-colors px-3 py-1.5 rounded-lg border"
  end
end
