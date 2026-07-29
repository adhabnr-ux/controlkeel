defmodule ControlKeelWeb.RecentSessions do
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: ControlKeelWeb.Endpoint,
    router: ControlKeelWeb.Router,
    statics: ControlKeelWeb.static_paths()

  attr :runs, :list, required: true

  def session_observability_section(assigns) do
    ~H"""
    <div id="observability-overview-run-list">
      <p class="text-xs font-semibold tracking-[0.14em] uppercase text-primary mb-4">
        Recent session runs
      </p>

      <div class="space-y-8">
        <%= if @runs == [] do %>
          <p class="text-muted-foreground text-sm">No sessions available yet.</p>
        <% else %>
          <div class="grid gap-2">
            <%= for run <- @runs do %>
              <div class="flex items-center justify-between gap-4 rounded-xl px-4 py-2 border bg-[rgba(255,255,255,0.015)] hover:bg-[rgba(255,255,255,0.03)] transition-colors">
                <div class="min-w-0 flex-1">
                  <.link
                    navigate={~p"/observability/sessions/#{run.id}"}
                    class="text-sm font-medium hover:text-primary transition-colors no-underline block truncate"
                  >
                    {run.title}
                  </.link>
                </div>
                <span class={health_pill_class(run.health)}>{run.health}</span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp health_pill_class("red") do
    "inline-flex items-center border border-[rgba(255,255,255,0.11)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  end

  defp health_pill_class("yellow") do
    "inline-flex items-center border border-[rgba(255,255,255,0.11)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  end

  defp health_pill_class(_) do
    "inline-flex items-center border border-[rgba(255,255,255,0.11)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  end
end
