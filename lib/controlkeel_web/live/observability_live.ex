defmodule ControlKeelWeb.ObservabilityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Observability.session_run(id) do
      {:ok, run} ->
        {:ok,
         socket
         |> assign(:page_title, "Observability — #{run.session.title}")
         |> assign(:run, run)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Session observability not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-run-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Session run observability</p>
            <h1 class="ck-section-title">{@run.session.title}</h1>
            <p class="ck-lead ck-lead-tight">{@run.session.objective}</p>
          </div>
          <div class="ck-badge-stack">
            <span class={obs_health_pill_class(@run.health.status)}>{@run.health.status}</span>
            <span class="ck-pill ck-pill-neutral">session ##{@run.session.id}</span>
            <.link navigate={~p"/missions/#{@run.session.id}"} class="ck-link">Open mission</.link>
            <.link
              id="observability-open-problems"
              navigate={~p"/observability/problems"}
              class="ck-link"
            >
              Open problems
            </.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-health-card" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Health</p>
            <strong>{@run.health.label}</strong>
            <ul class="ck-mini-list" style="margin-top: 0.75rem;">
              <%= for reason <- @run.health.reasons do %>
                <li>{reason}</li>
              <% end %>
            </ul>
          </div>

          <div id="observability-costs" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Budget</p>
            <strong>{@run.budget["decision"] || "unknown"}</strong>
            <p class="ck-note">
              {format_currency(@run.budget["spent_cents"] || 0)} / {format_currency(
                @run.budget["session_budget_cents"] || 0
              )} used
            </p>
            <p class="ck-note">
              Rolling 24h: {format_currency(@run.budget["rolling_24h_spend_cents"] || 0)} / {format_currency(
                @run.budget["daily_budget_cents"] || 0
              )}
            </p>
          </div>

          <div id="observability-findings" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Findings</p>
            <strong>{@run.findings.active} active / {@run.findings.total} total</strong>
            <p class="ck-note">
              {@run.findings.critical} critical · {@run.findings.high} high · {@run.findings.blocked} blocked
            </p>
            <.link navigate={~p"/findings"} class="ck-link">Open findings</.link>
          </div>

          <div id="observability-gates" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Gates</p>
            <strong>{@run.gates.pending_reviews} pending</strong>
            <p class="ck-note">{@run.gates.total_reviews} total review gates</p>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div id="observability-timeline" class="ck-card">
            <p class="ck-mini-label">Timeline</p>
            <%= if @run.timeline.recent == [] do %>
              <p class="ck-note">No timeline events recorded yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for event <- @run.timeline.recent do %>
                  <li>
                    <strong>{event.event_type || "event"}</strong>
                    <p class="ck-note">
                      {event.summary || "No summary"} · {event.actor || "unknown"} · {event.inserted_at ||
                        "unknown time"}
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="ck-side-stack">
            <div id="observability-tools" class="ck-card">
              <p class="ck-mini-label">Hosts, models, and tools</p>
              <div class="ck-brief-grid">
                <div>
                  <h3>Invocations</h3>
                  <p class="ck-note">{@run.hosts_models_tools.invocations}</p>
                </div>
                <div>
                  <h3>Estimated cost</h3>
                  <p class="ck-note">
                    {format_currency(@run.hosts_models_tools.estimated_cost_cents)}
                  </p>
                </div>
                <div>
                  <h3>Sources</h3>
                  <p class="ck-note">{format_frequency(@run.hosts_models_tools.by_source)}</p>
                </div>
                <div>
                  <h3>Models</h3>
                  <p class="ck-note">{format_frequency(@run.hosts_models_tools.by_model)}</p>
                </div>
                <div>
                  <h3>Tools</h3>
                  <p class="ck-note">{format_frequency(@run.hosts_models_tools.by_tool)}</p>
                </div>
              </div>
            </div>

            <div id="observability-memory-proof" class="ck-card">
              <p class="ck-mini-label">Context, memory, and proof</p>
              <div class="ck-brief-grid">
                <div>
                  <h3>Memory records</h3>
                  <p class="ck-note">{@run.memory.records}</p>
                </div>
                <div>
                  <h3>Proof bundles</h3>
                  <p class="ck-note">{@run.proofs.count}</p>
                  <.link navigate={~p"/proofs"} class="ck-link">Open proofs</.link>
                </div>
                <div>
                  <h3>Active tasks</h3>
                  <p class="ck-note">{@run.tasks.active} / {@run.tasks.total}</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div id="observability-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @run.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Recent findings</p>
            <%= if @run.findings.recent == [] do %>
              <p class="ck-note">No findings recorded yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for finding <- @run.findings.recent do %>
                  <li>
                    <strong>{finding.title}</strong>
                    <p class="ck-note">
                      {finding.severity} / {finding.status} · {finding.rule_id}
                    </p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="ck-card">
            <p class="ck-mini-label">Recent review gates</p>
            <%= if @run.gates.latest == [] do %>
              <p class="ck-note">No review gates recorded yet.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for review <- @run.gates.latest do %>
                  <li>
                    <.link navigate={~p"/reviews/#{review.id}"} class="ck-link">
                      {review.title}
                    </.link>
                    <p class="ck-note">{review.review_type} / {review.status}</p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp obs_health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp obs_health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp obs_health_pill_class(_status), do: "ck-pill ck-pill-low"

  defp format_currency(cents) when is_integer(cents), do: cents |> Kernel./(100) |> Float.round(2)
  defp format_currency(_cents), do: 0.0

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
