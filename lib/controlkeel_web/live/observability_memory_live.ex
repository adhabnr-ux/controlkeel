defmodule ControlKeelWeb.ObservabilityMemoryLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket = socket |> assign(:session_id, nil) |> assign(:session_title, nil)

    case Observability.memory_context(id, limit: 20) do
      {:ok, memory_context} ->
        {:ok,
         socket
         |> assign(:page_title, "Observability Memory")
         |> assign(:memory_context, memory_context)
         |> assign(:session_id, memory_context.session.id)
         |> assign(:session_title, memory_context.session.title)}

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
    <section
      id="observability-memory-page"
      class="border border-[var(--border)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-[var(--primary)]">Context and memory</h1>
          <p class="text-[var(--muted-foreground)] text-sm mt-1">
            Summary-only memory and context posture for {@memory_context.session.title}.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span id="observability-memory-total" class={neutral_pill_class()}>
            {@memory_context.memory.active} active memory
          </span>
        </div>
      </div>

      <CommandPill.command_pill command={"controlkeel obs memory #{@memory_context.session.id}"} />

      <div id="observability-memory-summary" class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div class="rounded-xl p-4 border border-[var(--border)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--muted-foreground)] uppercase tracking-[0.1em] text-[10px]">Memory</p>
          <p class="text-2xl font-semibold text-[var(--foreground)]">
            {@memory_context.memory.active} active
          </p>
          <p class="text-[var(--muted-foreground)] text-xs">
            {@memory_context.memory.archived} archived / {@memory_context.memory.count} recent
          </p>
        </div>
        <div class="rounded-xl p-4 border border-[var(--border)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--muted-foreground)] uppercase tracking-[0.1em] text-[10px]">Context</p>
          <p class="text-2xl font-semibold text-[var(--foreground)]">
            {@memory_context.context.tasks} task(s)
          </p>
          <p class="text-[var(--muted-foreground)] text-xs">
            {@memory_context.context.findings} finding(s), {@memory_context.context.reviews} review(s)
          </p>
        </div>
        <div class="rounded-xl p-4 border border-[var(--border)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--muted-foreground)] uppercase tracking-[0.1em] text-[10px]">Types</p>
          <p class="text-2xl font-semibold text-[var(--foreground)]">
            {map_size(@memory_context.memory.by_type)}
          </p>
          <p class="text-[var(--muted-foreground)] text-xs">
            {format_frequency(@memory_context.memory.by_type)}
          </p>
        </div>
        <div class="rounded-xl p-4 border border-[var(--border)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--muted-foreground)] uppercase tracking-[0.1em] text-[10px]">Sources</p>
          <p class="text-2xl font-semibold text-[var(--foreground)]">
            {map_size(@memory_context.memory.by_source)}
          </p>
          <p class="text-[var(--muted-foreground)] text-xs">
            {format_frequency(@memory_context.memory.by_source)}
          </p>
        </div>
      </div>

      <%= if @memory_context.recommendations != [] do %>
        <div id="observability-memory-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
            Recommended next actions
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @memory_context.recommendations do %>
              <li class="text-[var(--muted-foreground)] text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div id="observability-memory-records" class="space-y-3">
        <div class="flex items-center justify-between gap-4">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
            Recent memory records
          </p>
          <.link
            navigate={~p"/observability/memory-quality"}
            class="text-sm text-[var(--primary)] font-semibold hover:opacity-80 transition-opacity"
          >
            Memory quality →
          </.link>
        </div>
        <div class="space-y-3 max-h-[550px] overflow-y-auto pr-1">
          <%= if @memory_context.memory.recent == [] do %>
            <p class="text-[var(--muted-foreground)] text-sm">
              No memory records are available for this session.
            </p>
          <% else %>
            <%= for record <- @memory_context.memory.recent do %>
              <div
                id={"observability-memory-record-#{record.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--border)] bg-[rgba(255,255,255,0.015)] space-y-1"
              >
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="text-[var(--muted-foreground)] uppercase tracking-[0.1em] text-[10px]">
                      {record.record_type}
                    </p>
                    <p class="text-sm font-semibold text-[var(--foreground)]">{record.title}</p>
                  </div>
                  <span class={neutral_pill_class()}>
                    {if record.archived, do: "archived", else: "active"}
                  </span>
                </div>
                <p class="text-sm text-[var(--foreground)] leading-relaxed">{record.summary}</p>
                <p class="text-[var(--muted-foreground)] text-xs">
                  Source: {record.source_type || "unknown"} · Tags: {Enum.join(record.tags, ", ")}
                </p>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </section>
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
