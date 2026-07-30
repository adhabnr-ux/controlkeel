defmodule ControlKeelWeb.MissionsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:recent_sessions, Mission.list_all_sessions())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 md:py-12">
      <div class="mb-6 flex items-center justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-primary">
            Missions
          </p>
        </div>

        <a
          href={~p"/missions/start"}
          class="inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
        >
          <.icon name="hero-plus" class="size-4" /> New Mission
        </a>
      </div>

      <section class="rounded-3xl border bg-card/70 shadow-2xl shadow-black/20 backdrop-blur">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted/[0.03] text-xs uppercase tracking-[0.14em] text-muted-foreground">
              <tr>
                <th class="px-5 py-3 font-semibold">Mission</th>
                <th class="px-5 py-3 font-semibold">Risk</th>
                <th class="px-5 py-3 font-semibold">Workload</th>
                <th class="px-5 py-3 font-semibold">Findings</th>
                <th class="px-5 py-3 font-semibold">Budget</th>
                <th class="px-5 py-3 font-semibold"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= if @recent_sessions == [] do %>
                <tr>
                  <td colspan="6" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-foreground">No missions yet.</p>
                    <p class="mt-1 text-sm text-muted-foreground">
                      Start a mission to populate live governance telemetry.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for session <- @recent_sessions do %>
                  <tr class="transition hover:bg-muted/[0.03]">
                    <td class="max-w-sm px-5 py-4">
                      <p class="font-medium text-foreground">{session.title}</p>
                      <p class="mt-1 line-clamp-1 text-xs text-muted-foreground">
                        {session.objective}
                      </p>
                      <p class="mt-2 text-xs text-muted-foreground">
                        {session.workspace && session.workspace.name}
                      </p>
                    </td>
                    <td class="px-5 py-4">
                      <span class={[
                        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                        session.risk_tier in ["critical", "high"] &&
                          "bg-destructive/10 text-destructive ring-destructive/20",
                        session.risk_tier in ["medium", "moderate"] &&
                          "bg-[var(--ck-warning)]/10 text-[var(--ck-warning)] ring-[var(--ck-warning)]/20",
                        session.risk_tier in ["low"] &&
                          "bg-[var(--ck-success)]/10 text-[var(--ck-success)] ring-[var(--ck-success)]/20",
                        session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-muted text-muted-foreground ring-border"
                      ]}>
                        {session.risk_tier}
                      </span>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                        {Enum.count(session.tasks)} tasks
                      </div>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-exclamation-circle" class="size-4 text-muted-foreground" />
                        {Enum.count(session.findings)}
                      </div>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      ${session.budget_cents |> Kernel./(100) |> trunc()}
                    </td>
                    <td class="px-5 py-4 text-right">
                      <a
                        href={~p"/missions/#{session.id}"}
                        class="inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs font-semibold text-muted-foreground transition hover:border-primary/40 hover:bg-primary/10 hover:text-foreground"
                      >
                        Inspect <.icon name="hero-arrow-right" class="size-3" />
                      </a>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </section>
    """
  end
end
