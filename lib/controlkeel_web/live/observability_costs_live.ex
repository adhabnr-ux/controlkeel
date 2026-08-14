defmodule ControlKeelWeb.ObservabilityCostsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @groupings ~w(model tool source provider)

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    base_opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []

    grouped_costs =
      Enum.map(@groupings, fn group ->
        {group, Observability.costs(Keyword.put(base_opts, :by, group))}
      end)

    primary_costs = grouped_costs |> List.first() |> elem(1)

    {:ok,
     socket
     |> assign(:page_title, "Observability Costs")
     |> assign(:costs, primary_costs)
     |> assign(:grouped_costs, grouped_costs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="observability-costs" class="w-full space-y-8">
      <div class="space-y-2">
        <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">Costs</h1>
        <p class="text-sm text-muted-foreground">
          Estimated spend, token usage, and invocation counts grouped by model, tool, source, or provider.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs costs" />
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Invocations</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.invocations}</p>
          <p class="text-xs text-muted-foreground">{@costs.totals.sessions} session(s)</p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Estimated spend</p>
          <p class="text-2xl font-semibold text-foreground/90">
            {format_currency(@costs.totals.estimated_cost_cents)}
          </p>
          <p class="text-xs text-muted-foreground">Local invocation estimate</p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Input tokens</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.input_tokens}</p>
          <p class="text-xs text-muted-foreground">
            {@costs.totals.cached_input_tokens} cached
          </p>
        </section>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-1">
          <p class="text-sm font-medium text-muted-foreground">Output tokens</p>
          <p class="text-2xl font-semibold text-foreground/90">{@costs.totals.output_tokens}</p>
          <p class="text-xs text-muted-foreground">Across recorded calls</p>
        </section>
      </div>

      <%= if @costs.recommendations != [] do %>
        <section class="rounded-2xl border bg-card p-5 shadow-card space-y-3">
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @costs.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <div class="space-y-4">
        <.section_title>Group breakdown</.section_title>
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <%= for {grouping, costs} <- @grouped_costs do %>
            <section class="rounded-2xl border bg-card p-5 shadow-card space-y-4">
              <div class="flex items-center justify-between gap-2">
                <p class="text-sm font-medium text-muted-foreground">Grouped by {grouping}</p>
                <span class="rounded-full bg-muted px-3 py-1.5 text-sm font-medium text-foreground">
                  {length(costs.groups)} group(s)
                </span>
              </div>

              <%= if costs.groups == [] do %>
                <p class="text-sm text-muted-foreground">
                  No invocation cost data has been recorded yet.
                </p>
              <% else %>
                <div class="divide-y divide-border">
                  <%= for group <- costs.groups do %>
                    <div class="py-2.5 first:pt-0 last:pb-0">
                      <p class="text-sm font-medium text-foreground">{group.name}</p>
                      <p class="mt-1 text-xs text-muted-foreground">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.input_tokens} input · {group.output_tokens} output
                      </p>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
