defmodule ControlKeelWeb.ObservabilityMemoryLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Observability.memory_context(id, limit: 20) do
      {:ok, memory_context} ->
        {:ok,
         socket
         |> assign(:page_title, "Observability Memory")
         |> assign(:memory_context, memory_context)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Session memory observability not found.")
         |> push_navigate(to: ~p"/observability")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-memory-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Context and memory</h1>
            <p class="ck-lead ck-lead-tight">
              Summary-only memory and context posture for {@memory_context.session.title}.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-memory-total" class="ck-pill ck-pill-neutral">
              {@memory_context.memory.active} active memory
            </span>
            <.link
              navigate={~p"/observability/sessions/#{@memory_context.session.id}"}
              class="ck-link"
            >
              Run
            </.link>
            <.link navigate={~p"/observability/memory-quality"} class="ck-link">Memory quality</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-memory-summary" class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Memory</p>
            <strong>{@memory_context.memory.active} active</strong>
            <p class="ck-note">
              {@memory_context.memory.archived} archived / {@memory_context.memory.count} recent
            </p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Context</p>
            <strong>{@memory_context.context.tasks} task(s)</strong>
            <p class="ck-note">
              {@memory_context.context.findings} finding(s), {@memory_context.context.reviews} review(s)
            </p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Types</p>
            <strong>{map_size(@memory_context.memory.by_type)}</strong>
            <p class="ck-note">{format_frequency(@memory_context.memory.by_type)}</p>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Sources</p>
            <strong>{map_size(@memory_context.memory.by_source)}</strong>
            <p class="ck-note">{format_frequency(@memory_context.memory.by_source)}</p>
          </div>
        </div>

        <div id="observability-memory-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommended next actions</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @memory_context.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-memory-records" class="ck-card">
          <%= if @memory_context.memory.recent == [] do %>
            <p class="ck-note">No memory records are available for this session.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for record <- @memory_context.memory.recent do %>
                <li id={"observability-memory-record-#{record.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{record.record_type}</p>
                      <strong>{record.title}</strong>
                    </div>
                    <span class="ck-pill ck-pill-neutral">
                      {if record.archived, do: "archived", else: "active"}
                    </span>
                  </div>
                  <p>{record.summary}</p>
                  <p class="ck-note">
                    Source: {record.source_type || "unknown"} · Tags: {Enum.join(record.tags, ", ")}
                  </p>
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
