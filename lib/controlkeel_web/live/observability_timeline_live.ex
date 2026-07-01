defmodule ControlKeelWeb.ObservabilityTimelineLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

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
    <ObservabilitySessionLayout.session
      flash={@flash}
      current_path={"/observability/sessions/#{@timeline.session.id}/timeline"}
      session_id={@timeline.session.id}
      session_title={@timeline.session.title}
    >
      <section
        id="observability-timeline-page"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Timeline</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Recent governed events for {@timeline.session.title}.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span id="observability-timeline-total" class={neutral_pill_class()}>
              {@timeline.count} event(s)
            </span>
          </div>
        </div>

        <CommandPill.command_pill command={"controlkeel obs timeline #{@timeline.session.id}"} />

        <div id="observability-timeline-summary" class="grid grid-cols-3 gap-4">
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Events</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@timeline.count}</p>
            <p class="text-[var(--ck-muted)] text-xs">Limit {@timeline.limit}</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Event types</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {map_size(@timeline.by_event_type)}
            </p>
            <p class="text-[var(--ck-muted)] text-xs">{format_frequency(@timeline.by_event_type)}</p>
          </div>
          <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Actors</p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{map_size(@timeline.by_actor)}</p>
            <p class="text-[var(--ck-muted)] text-xs">{format_frequency(@timeline.by_actor)}</p>
          </div>
        </div>

        <div id="observability-timeline-events" class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Event stream
          </p>
          <%= if @timeline.events == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No timeline events recorded yet.</p>
          <% else %>
            <%= for event <- @timeline.events do %>
              <div
                id={"observability-timeline-event-#{event.id || event.event_type}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      {event.actor}
                    </p>
                    <p class="text-sm font-semibold text-[var(--ck-text)]">{event.event_type}</p>
                  </div>
                  <span class={neutral_pill_class()}>{format_datetime(event.inserted_at, "unknown time")}</span>
                </div>
                <p class="text-sm text-[var(--ck-text)] leading-relaxed">{event.summary}</p>
                <%= if event.body not in [nil, ""] do %>
                  <p class="text-[var(--ck-muted)] text-xs">{event.body}</p>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilitySessionLayout.session>
    """
  end

  defp neutral_pill_class,
    do:
      "inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(255,255,255,0.04)] text-[var(--ck-text)]"

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
