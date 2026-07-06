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
    <DashboardLayout.dashboard flash={@flash}>
      <section class="mx-auto max-w-7xl px-4 py-8 md:py-12">
        <div class="mb-6 flex items-center justify-between gap-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
              Missions
            </p>
          </div>

          <a
            href={~p"/missions/start"}
            class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-4 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
          >
            <.icon name="hero-plus" class="size-4" /> New Mission
          </a>
        </div>

        <section class="rounded-3xl border border-white/10 bg-zinc-900/70 shadow-2xl shadow-black/20 backdrop-blur">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-white/10 text-left text-sm">
              <thead class="bg-white/[0.03] text-xs uppercase tracking-[0.14em] text-zinc-500">
                <tr>
                  <th class="px-5 py-3 font-semibold">Mission</th>
                  <th class="px-5 py-3 font-semibold">Risk</th>
                  <th class="px-5 py-3 font-semibold">Workload</th>
                  <th class="px-5 py-3 font-semibold">Findings</th>
                  <th class="px-5 py-3 font-semibold">Budget</th>
                  <th class="px-5 py-3 font-semibold"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/10">
                <%= if @recent_sessions == [] do %>
                  <tr>
                    <td colspan="6" class="px-5 py-12 text-center">
                      <p class="text-base font-medium text-white">No missions yet.</p>
                      <p class="mt-1 text-sm text-zinc-500">
                        Start a mission to populate live governance telemetry.
                      </p>
                    </td>
                  </tr>
                <% else %>
                  <%= for session <- @recent_sessions do %>
                    <tr class="transition hover:bg-white/[0.03]">
                      <td class="max-w-sm px-5 py-4">
                        <p class="font-medium text-white">{session.title}</p>
                        <p class="mt-1 line-clamp-1 text-xs text-zinc-500">{session.objective}</p>
                        <p class="mt-2 text-xs text-zinc-600">
                          {session.workspace && session.workspace.name}
                        </p>
                      </td>
                      <td class="px-5 py-4">
                        <span class={[
                          "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                          session.risk_tier in ["critical", "high"] &&
                            "bg-red-400/10 text-red-200 ring-red-300/20",
                          session.risk_tier in ["medium", "moderate"] &&
                            "bg-amber-300/10 text-amber-100 ring-amber-200/20",
                          session.risk_tier in ["low"] &&
                            "bg-emerald-300/10 text-emerald-100 ring-emerald-200/20",
                          session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                            "bg-white/10 text-zinc-300 ring-white/15"
                        ]}>
                          {session.risk_tier}
                        </span>
                      </td>
                      <td class="px-5 py-4">
                        <div class="flex items-center gap-2 text-zinc-300">
                          <.icon name="hero-list-bullet" class="size-4 text-zinc-500" />
                          {Enum.count(session.tasks)} tasks
                        </div>
                      </td>
                      <td class="px-5 py-4">
                        <div class="flex items-center gap-2 text-zinc-300">
                          <.icon name="hero-exclamation-circle" class="size-4 text-zinc-500" />
                          {Enum.count(session.findings)}
                        </div>
                      </td>
                      <td class="px-5 py-4 text-zinc-300">
                        ${session.budget_cents |> Kernel./(100) |> trunc()}
                      </td>
                      <td class="px-5 py-4 text-right">
                        <a
                          href={~p"/missions/#{session.id}"}
                          class="inline-flex items-center gap-1 rounded-full border border-white/10 px-3 py-1.5 text-xs font-semibold text-zinc-300 transition hover:border-lime-300/40 hover:bg-lime-300/10 hover:text-white"
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
    </DashboardLayout.dashboard>
    """
  end
end
