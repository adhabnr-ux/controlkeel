defmodule ControlKeelWeb.ObservabilityCompareLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @groupings ~w(source model provider tool)

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    base_opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []

    comparisons =
      Enum.map(@groupings, fn group ->
        {group, Observability.comparison(Keyword.put(base_opts, :by, group))}
      end)

    primary = comparisons |> List.first() |> elem(1)

    {:ok,
     socket
     |> assign(:page_title, "Observability Compare")
     |> assign(:comparison, primary)
     |> assign(:comparisons, comparisons)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash}>
      <section
        id="observability-compare"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-6">
              Compare
            </p>
            <h1 class="text-xl font-semibold text-[var(--ck-text)]">Compare invocations</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Local host, model, provider, and tool comparison from recorded invocation metrics.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@comparison.totals.invocations} invocation(s)
            </span>
            <.link
              navigate={~p"/observability/costs"}
              class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
            >
              Costs →
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
          controlkeel obs compare
        </div>

        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Invocations</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@comparison.totals.invocations}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">{@comparison.totals.sessions} session(s)</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Estimated spend
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {format_currency(@comparison.totals.estimated_cost_cents)}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">Across compared calls</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Tokens</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@comparison.totals.input_tokens + @comparison.totals.cached_input_tokens +
                @comparison.totals.output_tokens}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">Input, cached, and output</p>
          </div>
        </div>

        <%= if @comparison.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <%= for recommendation <- @comparison.recommendations do %>
              <p class="text-[var(--ck-text)] text-sm leading-relaxed">{recommendation}</p>
            <% end %>
          </div>
        <% end %>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= for {grouping, comparison} <- @comparisons do %>
            <div
              id={"observability-compare-by-#{grouping}"}
              class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-3"
            >
              <div class="flex items-center justify-between gap-2">
                <div>
                  <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                    Compared by
                  </p>
                  <p class="text-base font-semibold text-[var(--ck-text)] capitalize">{grouping}</p>
                </div>
                <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-2.5 py-1 text-xs bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
                  {length(comparison.groups)} group(s)
                </span>
              </div>

              <%= if comparison.groups == [] do %>
                <p class="text-[var(--ck-muted)] text-sm">
                  No invocation data is available for comparison yet.
                </p>
              <% else %>
                <div class="space-y-2">
                  <%= for group <- comparison.groups do %>
                    <div class="border-t border-[var(--ck-stroke)] pt-2 space-y-1">
                      <p class="text-sm font-semibold text-[var(--ck-text)]">{group.name}</p>
                      <p class="text-[var(--ck-muted)] text-xs">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.cost_per_call_cents} cent(s)/call · {group.tokens_per_call} token(s)/call
                      </p>
                      <%= if group.decisions && group.decisions != %{} do %>
                        <p class="text-[var(--ck-muted)] text-xs">
                          Decisions: {format_frequency(group.decisions)}
                        </p>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
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
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
