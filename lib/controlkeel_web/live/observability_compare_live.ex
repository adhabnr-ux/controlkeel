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
    <Layouts.app flash={@flash}>
      <section id="observability-compare-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Compare invocations</h1>
            <p class="ck-lead ck-lead-tight">
              Local host, model, provider, and tool comparison from recorded invocation metrics.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-compare-total" class="ck-pill ck-pill-neutral">
              {@comparison.totals.invocations} invocation(s)
            </span>
            <.link navigate={~p"/observability/costs"} class="ck-link">Costs</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-compare-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Invocations</p>
            <strong>{@comparison.totals.invocations}</strong>
            <p class="ck-note">{@comparison.totals.sessions} session(s)</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Estimated spend</p>
            <strong>{format_currency(@comparison.totals.estimated_cost_cents)}</strong>
            <p class="ck-note">Across compared calls</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Tokens</p>
            <strong>
              {@comparison.totals.input_tokens + @comparison.totals.cached_input_tokens +
                @comparison.totals.output_tokens}
            </strong>
            <p class="ck-note">Input, cached, and output</p>
          </div>
        </div>

        <div id="observability-compare-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommended next actions</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @comparison.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-compare-groups" class="ck-grid ck-grid-dashboard">
          <%= for {grouping, comparison} <- @comparisons do %>
            <div id={"observability-compare-by-#{grouping}"} class="ck-card">
              <div class="ck-card-header">
                <div>
                  <p class="ck-mini-label">Compared by</p>
                  <h2 class="ck-card-title">{grouping}</h2>
                </div>
                <span class="ck-pill ck-pill-neutral">{length(comparison.groups)} group(s)</span>
              </div>

              <%= if comparison.groups == [] do %>
                <p class="ck-note">No invocation data is available for comparison yet.</p>
              <% else %>
                <ul class="ck-mini-list">
                  <%= for group <- comparison.groups do %>
                    <li>
                      <strong>{group.name}</strong>
                      <p class="ck-note">
                        {group.invocations} call(s) · {format_currency(group.estimated_cost_cents)} · {group.cost_per_call_cents} cent(s)/call · {group.tokens_per_call} token(s)/call
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
