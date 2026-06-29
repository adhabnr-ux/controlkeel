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
    <ObservabilityLayout.observability flash={@flash} current_path="/observability/imports">
      <section
        id="observability-imports"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-6">
              Imports
            </p>
            <h1 class="text-xl font-semibold text-[var(--ck-text)]">Imported snapshots</h1>
            <p class="text-[var(--ck-muted)] text-sm mt-1">
              Local persisted observability envelopes, listed as summary-only evidence snapshots.
            </p>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@imports.count} persisted
            </span>
            <.link
              navigate={~p"/observability"}
              class="text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
            >
              Overview →
            </.link>
          </div>
        </div>

        <div class="text-[var(--ck-muted)] text-xs font-mono border border-[var(--ck-stroke)] rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
          controlkeel obs imports
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div
            id="observability-imports-integrity"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Integrity</p>
            <p class="text-base font-semibold text-[var(--ck-text)]">
              {format_frequency(@imports.by_integrity)}
            </p>
          </div>
          <div
            id="observability-imports-health"
            class="rounded-xl p-4 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-1"
          >
            <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">Health</p>
            <p class="text-base font-semibold text-[var(--ck-text)]">
              {format_frequency(@imports.by_health)}
            </p>
          </div>
        </div>

        <%= if @imports.recommendations != [] do %>
          <div class="space-y-2">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recommendations
            </p>
            <%= for recommendation <- @imports.recommendations do %>
              <p class="text-[var(--ck-text)] text-sm leading-relaxed">{recommendation}</p>
            <% end %>
          </div>
        <% end %>

        <div class="space-y-3">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Recent imports
          </p>
          <%= if @imports.recent == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No persisted observability imports yet.</p>
          <% else %>
            <%= for imported <- @imports.recent do %>
              <div
                id={"observability-import-#{imported.id}"}
                class="rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] space-y-2"
              >
                <p class="text-sm font-semibold text-[var(--ck-text)]">
                  {imported.original_session_title || "Unknown session"}
                </p>
                <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Imported
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.imported_at || "unknown time"}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Exported
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.exported_at || "unknown time"}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Session
                    </p>
                    <p class="text-[var(--ck-text)]">#{imported.original_session_id || "unknown"}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Health
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.health}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Problem groups
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.problem_groups}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Findings
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.total_problem_findings}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Integrity
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.integrity_status}</p>
                  </div>
                  <div class="col-span-2">
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Fingerprint
                    </p>
                    <p class="text-[var(--ck-text)] font-mono text-[10px] truncate">
                      {imported.payload_fingerprint || "unknown"}
                    </p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Mutation
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.mutation}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Schema
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.schema_version}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Source
                    </p>
                    <p class="text-[var(--ck-text)]">{source_label(imported.source)}</p>
                  </div>
                  <div>
                    <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                      Redaction
                    </p>
                    <p class="text-[var(--ck-text)]">{imported.redaction_policy || "unknown"}</p>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </ObservabilityLayout.observability>
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
