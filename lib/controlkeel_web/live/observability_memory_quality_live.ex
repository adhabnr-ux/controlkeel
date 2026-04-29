defmodule ControlKeelWeb.ObservabilityMemoryQualityLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

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
    <Layouts.app flash={@flash}>
      <section id="observability-memory-quality-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Memory quality</h1>
            <p class="ck-lead ck-lead-tight">
              Summary-only signals for stale, duplicate, superseded, and missed workspace memory.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-memory-quality-threshold" class="ck-pill ck-pill-neutral">
              stale ≥ {@quality.stale_days} days
            </span>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-memory-quality-total" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Memory records</p>
            <strong>{@quality.totals.records}</strong>
            <p class="ck-note">
              {@quality.totals.active} active · {@quality.totals.archived} archived
            </p>
          </div>
          <div id="observability-memory-quality-stale" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Stale candidates</p>
            <strong>{@quality.totals.stale_candidates}</strong>
          </div>
          <div id="observability-memory-quality-duplicates" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Duplicate clusters</p>
            <strong>{@quality.totals.duplicate_clusters}</strong>
          </div>
          <div id="observability-memory-quality-missed" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Missed-memory sessions</p>
            <strong>{@quality.totals.missed_memory_sessions}</strong>
          </div>
        </div>

        <div id="observability-memory-quality-distributions" class="ck-card">
          <p class="ck-mini-label">Distribution</p>
          <p class="ck-note">Types: {format_frequency(@quality.distributions.by_type)}</p>
          <p class="ck-note">Sources: {format_frequency(@quality.distributions.by_source)}</p>
        </div>

        <div id="observability-memory-quality-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @quality.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div id="observability-memory-quality-stale-list" class="ck-card">
            <p class="ck-mini-label">Stale memory</p>
            <%= if @quality.stale_candidates == [] do %>
              <p class="ck-note">No stale memory candidates detected.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for record <- @quality.stale_candidates do %>
                  <li id={"observability-memory-quality-stale-#{record.id}"}>
                    <strong>{record.title}</strong>
                    <p class="ck-note">
                      {record.record_type} · {record.age_days} day(s) old · {record.source_type}
                    </p>
                    <p>{record.summary}</p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div id="observability-memory-quality-duplicate-list" class="ck-card">
            <p class="ck-mini-label">Duplicate clusters</p>
            <%= if @quality.duplicate_clusters == [] do %>
              <p class="ck-note">No duplicate clusters detected.</p>
            <% else %>
              <ul class="ck-mini-list">
                <%= for cluster <- @quality.duplicate_clusters do %>
                  <li>
                    <strong>{cluster.key}</strong>
                    <p class="ck-note">{cluster.count} matching record(s)</p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>

        <div id="observability-memory-quality-contradictions" class="ck-card">
          <p class="ck-mini-label">Contradiction or superseded candidates</p>
          <%= if @quality.contradiction_candidates == [] do %>
            <p class="ck-note">No contradiction or superseded markers detected.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for record <- @quality.contradiction_candidates do %>
                <li id={"observability-memory-quality-contradiction-#{record.id}"}>
                  <strong>{record.title}</strong>
                  <p>{record.summary}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <div id="observability-memory-quality-missed-list" class="ck-card">
          <p class="ck-mini-label">Missed-memory sessions</p>
          <%= if @quality.missed_memory_sessions == [] do %>
            <p class="ck-note">No sessions with evidence but missing memory detected.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for session <- @quality.missed_memory_sessions do %>
                <li id={"observability-memory-quality-missed-#{session.id}"}>
                  <strong>{session.title}</strong>
                  <p class="ck-note">
                    {session.findings} finding(s) · {session.reviews} review(s) · {session.invocations} invocation(s)
                  </p>
                  <p>{session.recommendation}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
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
