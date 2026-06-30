defmodule ControlKeelWeb.ObservabilityCostsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

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
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/costs">
      <section
        id="observability-costs"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Costs</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Estimated spend, token usage, and invocation counts grouped by model, tool, source, or provider.
            </p>
          </div>
        </div>

        <div class="text-[var(--ck-muted)] text-xs font-mono border border-[var(--ck-stroke)] rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
          controlkeel obs costs
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Invocations</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@costs.totals.invocations}</p>
            <p class="text-[var(--ck-muted)] text-xs">{@costs.totals.sessions} session(s)</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Estimated spend
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {format_currency(@costs.totals.estimated_cost_cents)}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">Local invocation estimate</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Input tokens</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@costs.totals.input_tokens}</p>
            <p class="text-[var(--ck-muted)] text-xs">{@costs.totals.cached_input_tokens} cached</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Output tokens</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@costs.totals.output_tokens}</p>
            <p class="text-[var(--ck-muted)] text-xs">Across recorded calls</p>
          </div>
        </div>

        <%= if @costs.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <ul class="list-disc pl-5">
              <%= for recommendation <- @costs.recommendations do %>
                <li class="text-[var(--ck-muted)] text-sm leading-relaxed">{recommendation}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <div class="space-y-4">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Group breakdown
          </p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for {grouping, costs} <- @grouped_costs do %>
              <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-3">
                <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                  Grouped by {grouping}
                  <span class="ml-2 text-[var(--ck-lime)]">{length(costs.groups)} group(s)</span>
                </p>

                <%= if costs.groups == [] do %>
                  <p class="text-[var(--ck-muted)] text-sm">
                    No invocation cost data has been recorded yet.
                  </p>
                <% else %>
                  <div class="space-y-2">
                    <%= for group <- costs.groups do %>
                      <div class="flex items-center justify-between gap-2 p-2 rounded-lg border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.02)]">
                        <div>
                          <p class="text-sm font-medium text-[var(--ck-text)]">{group.name}</p>
                          <p class="text-[var(--ck-muted)] text-xs">
                            {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.input_tokens} input · {group.output_tokens} output
                          </p>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
