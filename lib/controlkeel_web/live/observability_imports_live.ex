defmodule ControlKeelWeb.ObservabilityImportsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    imports = Observability.imports(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability imports")
     |> assign(:imports, imports)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-imports-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Imported snapshots</h1>
            <p class="ck-lead ck-lead-tight">
              Local persisted observability envelopes, listed as summary-only evidence snapshots.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-imports-count" class="ck-pill ck-pill-neutral">
              {@imports.count} persisted
            </span>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-imports-integrity" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Integrity</p>
            <strong>{format_frequency(@imports.by_integrity)}</strong>
          </div>
          <div id="observability-imports-health" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Health</p>
            <strong>{format_frequency(@imports.by_health)}</strong>
          </div>
        </div>

        <div id="observability-imports-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @imports.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-imports-list" class="ck-card">
          <p class="ck-mini-label">Recent imports</p>
          <%= if @imports.recent == [] do %>
            <p class="ck-note">No persisted observability imports yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for imported <- @imports.recent do %>
                <li id={"observability-import-#{imported.id}"}>
                  <strong>{imported.original_session_title || "Unknown session"}</strong>
                  <p class="ck-note">
                    Imported {imported.imported_at || "unknown time"} · exported {imported.exported_at ||
                      "unknown time"}
                  </p>
                  <p class="ck-note">
                    Session #{imported.original_session_id || "unknown"} · {imported.health} · {imported.problem_groups} problem group(s) · {imported.total_problem_findings} finding(s)
                  </p>
                  <p class="ck-note">
                    Integrity {imported.integrity_status} · hash {imported.payload_fingerprint ||
                      "unknown"} · mutation {imported.mutation}
                  </p>
                  <p class="ck-note">
                    Schema {imported.schema_version} · source {source_label(imported.source)} · redaction {imported.redaction_policy ||
                      "unknown"}
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
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end

  defp source_label(source) when is_map(source) do
    [source["product"], source["surface"], source["mode"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" / ")
    |> case do
      "" -> "unknown"
      label -> label
    end
  end

  defp source_label(_source), do: "unknown"
end
