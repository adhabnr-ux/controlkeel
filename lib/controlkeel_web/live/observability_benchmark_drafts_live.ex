defmodule ControlKeelWeb.ObservabilityBenchmarkDraftsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeelWeb.CommandPill

  on_mount ControlKeelWeb.CommandPill

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    drafts = Observability.benchmark_drafts(opts)

    {:ok,
     socket
     |> assign(:page_title, "Benchmark Drafts")
     |> assign(:opts, opts)
     |> assign(:drafts, drafts)}
  end

  @impl true
  def handle_event("approve-draft", %{"id" => id}, socket) do
    opts = Keyword.merge(socket.assigns.opts, reviewed_by: "web")

    case Observability.update_benchmark_draft_status(id, "approved", opts) do
      {:ok, _result} ->
        {:noreply, assign(socket, :drafts, Observability.benchmark_drafts(socket.assigns.opts))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, flash_for_status_error(reason))}
    end
  end

  def handle_event("reject-draft", %{"id" => id}, socket) do
    opts = Keyword.merge(socket.assigns.opts, reviewed_by: "web")

    case Observability.update_benchmark_draft_status(id, "rejected", opts) do
      {:ok, _result} ->
        {:noreply, assign(socket, :drafts, Observability.benchmark_drafts(socket.assigns.opts))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, flash_for_status_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="observability-benchmark-drafts-page"
      class="border border-border rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold text-primary">Benchmark drafts</h1>
          <p class="text-muted-foreground text-sm mt-1">
            Human-gated local benchmark draft scenarios generated from saved eval candidates.
          </p>
        </div>
        <div class="flex items-center gap-3 shrink-0 flex-wrap justify-end">
          <span id="observability-benchmark-drafts-count" class={neutral_pill_class()}>
            {@drafts.count} draft(s)
          </span>
        </div>
      </div>

      <CommandPill.command_pill command="controlkeel obs benchmarks drafts" />

      <div class="grid grid-cols-2 gap-4">
        <div
          id="observability-benchmark-drafts-status"
          class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Status</p>
          <p class="text-lg font-semibold text-foreground">
            {format_frequency(@drafts.by_status)}
          </p>
        </div>
        <div
          id="observability-benchmark-drafts-suites"
          class="rounded-xl p-4 border border-border bg-[rgba(255,255,255,0.015)] space-y-1"
        >
          <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">Suites</p>
          <p class="text-lg font-semibold text-foreground">
            {format_frequency(@drafts.by_suite)}
          </p>
        </div>
      </div>

      <%= if @drafts.recommendations != [] do %>
        <div id="observability-benchmark-drafts-recommendations" class="space-y-2">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Recommendations
          </p>
          <ul class="list-disc pl-5">
            <%= for recommendation <- @drafts.recommendations do %>
              <li class="text-muted-foreground text-sm leading-relaxed">{recommendation}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div id="observability-benchmark-drafts-list" class="space-y-3">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Draft scenarios
        </p>
        <%= if @drafts.drafts == [] do %>
          <p class="text-muted-foreground text-sm">No benchmark drafts yet.</p>
        <% else %>
          <%= for draft <- @drafts.drafts do %>
            <div
              id={"observability-benchmark-draft-#{draft.id}"}
              class="rounded-xl px-4 py-3 border border-border bg-[rgba(255,255,255,0.015)] space-y-2"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-muted-foreground uppercase tracking-[0.1em] text-[10px]">
                    {draft.suite_slug}
                  </p>
                  <p class="text-sm font-semibold text-foreground">{draft.title}</p>
                </div>
                <span class={neutral_pill_class()}>{draft.status}</span>
              </div>
              <p class="text-sm text-foreground leading-relaxed">{draft.scenario_prompt}</p>
              <p class="text-muted-foreground text-xs">
                Expected: {draft.expected_behavior}
              </p>
              <p class="text-muted-foreground text-xs">
                Human gate required: {draft.human_gate_required}
              </p>
              <p class="text-muted-foreground text-xs">
                Scenario: {materialized_scenario(draft)}
              </p>
              <div class="flex items-center gap-3 pt-1">
                <button
                  id={"observability-benchmark-draft-approve-#{draft.id}"}
                  type="button"
                  class="inline-flex items-center rounded-lg px-3 py-1.5 text-sm font-semibold bg-[rgba(190,242,100,0.14)] text-primary border border-primary hover:opacity-80 transition-opacity"
                  phx-click="approve-draft"
                  phx-value-id={draft.id}
                >
                  Approve
                </button>
                <button
                  id={"observability-benchmark-draft-reject-#{draft.id}"}
                  type="button"
                  class="inline-flex items-center rounded-lg px-3 py-1.5 text-sm font-semibold border border-border bg-[rgba(255,255,255,0.03)] text-foreground hover:opacity-80 transition-opacity"
                  phx-click="reject-draft"
                  phx-value-id={draft.id}
                >
                  Reject
                </button>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </section>
    """
  end

  defp materialized_scenario(draft) do
    case get_in(draft.metadata || %{}, ["materialized_scenario_id"]) do
      id when is_integer(id) -> "##{id}"
      _ -> "not materialized"
    end
  end

  defp flash_for_status_error(:forbidden),
    do: "You can only review drafts from the current workspace."

  defp flash_for_status_error(:not_found), do: "Benchmark draft was not found."
  defp flash_for_status_error(:invalid_id), do: "The provided draft id was invalid."
  defp flash_for_status_error(_reason), do: "Unable to update benchmark draft status."

  defp format_frequency(map) when map == %{}, do: "none"

  defp format_frequency(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
