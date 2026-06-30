defmodule ControlKeelWeb.ObservabilityMemoryQualityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  use ControlKeelWeb.CommandPill

  @impl true
  def mount(params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    stale_days = parse_days(params["stale_days"])

    opts =
      if recent_session,
        do: [workspace_id: recent_session.workspace_id, stale_days: stale_days],
        else: [stale_days: stale_days]

    quality = Observability.memory_quality(opts)

    {:ok,
     socket
     |> assign(:page_title, "Memory quality")
     |> assign(:quality, quality)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/memory-quality">
      <section
        id="observability-memory-quality"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-xl font-semibold text-[var(--ck-lime)]">Memory quality</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Summary-only signals for stale, duplicate, superseded, and missed workspace memory.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              stale ≥ {@quality.stale_days} days
            </span>
          </div>
        </div>

        <CommandPill.command_pill command="controlkeel obs memory-quality" />

        <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div
            id="observability-memory-quality-total"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Memory records
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">{@quality.totals.records}</p>
            <p class="text-[var(--ck-muted)] text-xs">
              {@quality.totals.active} active · {@quality.totals.archived} archived
            </p>
          </div>
          <div
            id="observability-memory-quality-stale"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Stale candidates
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@quality.totals.stale_candidates}
            </p>
          </div>
          <div
            id="observability-memory-quality-duplicates"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Duplicate clusters
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@quality.totals.duplicate_clusters}
            </p>
          </div>
          <div
            id="observability-memory-quality-missed"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
              Missed-memory sessions
            </p>
            <p class="text-2xl font-semibold text-[var(--ck-text)]">
              {@quality.totals.missed_memory_sessions}
            </p>
          </div>
        </div>

        <div class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1">
          <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Distribution</p>
          <p class="text-[var(--ck-muted)] text-xs">
            Types: {format_frequency(@quality.distributions.by_type)}
          </p>
          <p class="text-[var(--ck-muted)] text-xs">
            Sources: {format_frequency(@quality.distributions.by_source)}
          </p>
        </div>

        <%= if @quality.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <%= for recommendation <- @quality.recommendations do %>
              <p class="text-[var(--ck-text)] text-sm leading-relaxed">{recommendation}</p>
            <% end %>
          </div>
        <% end %>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Stale memory
          </p>
          <%= if @quality.stale_candidates == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No stale memory candidates detected.</p>
          <% else %>
            <div class="space-y-2">
              <%= for record <- @quality.stale_candidates do %>
                <div
                  id={"observability-memory-quality-stale-#{record.id}"}
                  class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
                >
                  <p class="text-sm font-semibold text-[var(--ck-text)]">{record.title}</p>
                  <p class="text-[var(--ck-muted)] text-xs">
                    {record.record_type} · {record.age_days} day(s) old · {record.source_type}
                  </p>
                  <p class="text-[var(--ck-text)] text-xs">{record.summary}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Duplicate clusters
          </p>
          <%= if @quality.duplicate_clusters == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No duplicate clusters detected.</p>
          <% else %>
            <div class="space-y-2">
              <%= for cluster <- @quality.duplicate_clusters do %>
                <div class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)]">
                  <p class="text-sm font-semibold text-[var(--ck-text)]">{cluster.key}</p>
                  <p class="text-[var(--ck-muted)] text-xs">{cluster.count} matching record(s)</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Contradiction or superseded candidates
          </p>
          <%= if @quality.contradiction_candidates == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">
              No contradiction or superseded markers detected.
            </p>
          <% else %>
            <div class="space-y-2">
              <%= for record <- @quality.contradiction_candidates do %>
                <div
                  id={"observability-memory-quality-contradiction-#{record.id}"}
                  class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
                >
                  <p class="text-sm font-semibold text-[var(--ck-text)]">{record.title}</p>
                  <p class="text-[var(--ck-text)] text-xs">{record.summary}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Missed-memory sessions
          </p>
          <%= if @quality.missed_memory_sessions == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">
              No sessions with evidence but missing memory detected.
            </p>
          <% else %>
            <div class="space-y-2">
              <%= for session <- @quality.missed_memory_sessions do %>
                <div
                  id={"observability-memory-quality-missed-#{session.id}"}
                  class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
                >
                  <p class="text-sm font-semibold text-[var(--ck-text)]">{session.title}</p>
                  <p class="text-[var(--ck-muted)] text-xs">
                    {session.findings} finding(s) · {session.reviews} review(s) · {session.invocations} invocation(s)
                  </p>
                  <p class="text-[var(--ck-text)] text-xs">{session.recommendation}</p>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
    """
  end

  defp parse_days(nil), do: 30

  defp parse_days(value) do
    case Integer.parse(to_string(value)) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
  end

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
