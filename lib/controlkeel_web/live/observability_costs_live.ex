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
    <Layouts.app flash={@flash}>
      <section id="observability-costs-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Costs and efficiency</h1>
            <p class="ck-lead ck-lead-tight">
              Local invocation spend, token shape, and grouped efficiency signals.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-costs-total" class="ck-pill ck-pill-neutral">
              {format_currency(@costs.totals.estimated_cost_cents)} estimated
            </span>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-costs-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Invocations</p>
            <strong>{@costs.totals.invocations}</strong>
            <p class="ck-note">{@costs.totals.sessions} session(s)</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Estimated spend</p>
            <strong>{format_currency(@costs.totals.estimated_cost_cents)}</strong>
            <p class="ck-note">Local invocation estimate</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Input tokens</p>
            <strong>{@costs.totals.input_tokens}</strong>
            <p class="ck-note">{@costs.totals.cached_input_tokens} cached</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Output tokens</p>
            <strong>{@costs.totals.output_tokens}</strong>
            <p class="ck-note">Across recorded calls</p>
          </div>
        </div>

        <div id="observability-costs-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommended next actions</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @costs.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-costs-groups" class="ck-grid ck-grid-dashboard">
          <%= for {grouping, costs} <- @grouped_costs do %>
            <div id={"observability-costs-by-#{grouping}"} class="ck-card">
              <div class="ck-card-header">
                <div>
                  <p class="ck-mini-label">Grouped by</p>
                  <h2 class="ck-card-title">{grouping}</h2>
                </div>
                <span class="ck-pill ck-pill-neutral">{length(costs.groups)} group(s)</span>
              </div>

              <%= if costs.groups == [] do %>
                <p class="ck-note">No invocation cost data has been recorded yet.</p>
              <% else %>
                <ul class="ck-mini-list">
                  <%= for group <- costs.groups do %>
                    <li>
                      <strong>{group.name}</strong>
                      <p class="ck-note">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.input_tokens} input · {group.output_tokens} output
                      </p>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0
end
