defmodule ControlKeelWeb.ObservabilityImportsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

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
    <section
      id="observability-imports"
      class="border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-primary">Imported snapshots</h1>
          <p class="text-muted-foreground text-sm mt-1">
            Local persisted observability envelopes, listed as summary-only evidence snapshots.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span class="inline-flex items-center border rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
            {@imports.count} persisted
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs imports" />

      <div class="grid grid-cols-2 gap-4">
        <div
          id="observability-imports-integrity"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
            Integrity
          </p>
          <p class="text-base font-semibold">
            {format_frequency(@imports.by_integrity)}
          </p>
        </div>
        <div
          id="observability-imports-health"
          class="rounded-xl p-4 border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Health</p>
          <p class="text-base font-semibold">
            {format_frequency(@imports.by_health)}
          </p>
        </div>
      </div>

      <%= if @imports.recommendations != [] do %>
        <div class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @imports.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Recent imports
        </p>
        <%= if @imports.recent == [] do %>
          <p class="text-muted-foreground text-sm">
            No persisted observability imports yet.
          </p>
        <% else %>
          <%= for imported <- @imports.recent do %>
            <div
              id={"observability-import-#{imported.id}"}
              class="rounded-xl px-4 py-3 border bg-[rgba(255,255,255,0.015)] space-y-2"
            >
              <p class="text-sm font-semibold">
                {imported.original_session_title || "Unknown session"}
              </p>
              <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Imported
                  </p>
                  <p>{imported.imported_at || "unknown time"}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Exported
                  </p>
                  <p>{imported.exported_at || "unknown time"}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Session
                  </p>
                  <p>#{imported.original_session_id || "unknown"}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Health
                  </p>
                  <p>{imported.health}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Problem groups
                  </p>
                  <p>{imported.problem_groups}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Findings
                  </p>
                  <p>{imported.total_problem_findings}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Integrity
                  </p>
                  <p>{imported.integrity_status}</p>
                </div>
                <div class="col-span-2">
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Fingerprint
                  </p>
                  <p class=" font-mono text-[10px] truncate">
                    {imported.payload_fingerprint || "unknown"}
                  </p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Mutation
                  </p>
                  <p>{imported.mutation}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Schema
                  </p>
                  <p>{imported.schema_version}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Source
                  </p>
                  <p>{source_label(imported.source)}</p>
                </div>
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    Redaction
                  </p>
                  <p>{imported.redaction_policy || "unknown"}</p>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
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
