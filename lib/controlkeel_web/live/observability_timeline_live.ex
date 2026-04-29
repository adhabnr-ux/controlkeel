defmodule ControlKeelWeb.ObservabilityTimelineLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Observability.timeline(id, limit: 50) do
      {:ok, timeline} ->
        {:ok,
         socket
         |> assign(:page_title, "Observability Timeline")
         |> assign(:timeline, timeline)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Session timeline not found.")
         |> push_navigate(to: ~p"/observability")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-timeline-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Timeline</h1>
            <p class="ck-lead ck-lead-tight">
              Recent governed events for {@timeline.session.title}.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-timeline-total" class="ck-pill ck-pill-neutral">
              {@timeline.count} event(s)
            </span>
            <.link navigate={~p"/observability/sessions/#{@timeline.session.id}"} class="ck-link">
              Run
            </.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-timeline-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Events</p>
            <strong>{@timeline.count}</strong>
            <p class="ck-note">Limit {@timeline.limit}</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Event types</p>
            <strong>{map_size(@timeline.by_event_type)}</strong>
            <p class="ck-note">{format_frequency(@timeline.by_event_type)}</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Actors</p>
            <strong>{map_size(@timeline.by_actor)}</strong>
            <p class="ck-note">{format_frequency(@timeline.by_actor)}</p>
          </div>
        </div>

        <div id="observability-timeline-events" class="ck-card">
          <%= if @timeline.events == [] do %>
            <p class="ck-note">No timeline events recorded yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for event <- @timeline.events do %>
                <li id={"observability-timeline-event-#{event.id || event.event_type}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{event.actor}</p>
                      <strong>{event.event_type}</strong>
                    </div>
                    <span class="ck-pill ck-pill-neutral">{event.inserted_at || "unknown time"}</span>
                  </div>
                  <p>{event.summary}</p>
                  <%= if event.body not in [nil, ""] do %>
                    <p class="ck-note">{event.body}</p>
                  <% end %>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
