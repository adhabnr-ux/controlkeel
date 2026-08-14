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
    <section id="observability-benchmark-drafts-page" class="w-full space-y-5">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div class="space-y-2">
          <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
            Benchmark drafts
          </h1>
          <p class="text-sm text-muted-foreground">
            Human-gated local benchmark draft scenarios generated from saved eval candidates.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-3 shrink-0 justify-end">
          <span id="observability-benchmark-drafts-count" class={neutral_pill_class()}>
            {@drafts.count} draft(s)
          </span>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <CommandPill.command_pill command="controlkeel obs benchmarks drafts" />
      </div>

      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <article
          id="observability-benchmark-drafts-status"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Status</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@drafts.by_status)}
          </p>
        </article>
        <article
          id="observability-benchmark-drafts-suites"
          class="rounded-2xl border bg-card p-5 shadow-card"
        >
          <p class="text-sm font-medium text-muted-foreground">Suites</p>
          <p class="mt-2 text-lg font-semibold text-foreground/90">
            {format_frequency(@drafts.by_suite)}
          </p>
        </article>
      </div>

      <%= if @drafts.recommendations != [] do %>
        <section
          id="observability-benchmark-drafts-recommendations"
          class="rounded-2xl border bg-card p-5 shadow-card space-y-3"
        >
          <.section_title>Recommendations</.section_title>
          <%= for recommendation <- @drafts.recommendations do %>
            <p class="text-sm leading-relaxed text-muted-foreground">{recommendation}</p>
          <% end %>
        </section>
      <% end %>

      <section
        id="observability-benchmark-drafts-list"
        class="rounded-2xl border bg-card p-5 shadow-card space-y-4"
      >
        <.section_title>Draft scenarios</.section_title>
        <%= if @drafts.drafts == [] do %>
          <p class="text-sm text-muted-foreground">No benchmark drafts yet.</p>
        <% else %>
          <div class="divide-y divide-border">
            <%= for draft <- @drafts.drafts do %>
              <div
                id={"observability-benchmark-draft-#{draft.id}"}
                class="space-y-2 py-3 first:pt-0 last:pb-0"
              >
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0 space-y-1">
                    <p class="text-[10px] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                      {draft.suite_slug}
                    </p>
                    <p class="text-sm font-medium text-foreground">{draft.title}</p>
                  </div>
                  <span class={status_pill_class(draft.status)}>{draft.status}</span>
                </div>
                <p class="text-sm leading-relaxed text-foreground">{draft.scenario_prompt}</p>
                <p class="text-xs text-muted-foreground">
                  Expected: {draft.expected_behavior}
                </p>
                <p class="text-xs text-muted-foreground">
                  Human gate required: {draft.human_gate_required}
                </p>
                <p class="text-xs text-muted-foreground">
                  Scenario: {materialized_scenario(draft)}
                </p>
                <div class="flex items-center gap-3 pt-1">
                  <button
                    id={"observability-benchmark-draft-approve-#{draft.id}"}
                    type="button"
                    class="inline-flex items-center rounded-lg bg-primary px-3 py-1.5 text-sm font-semibold text-primary-foreground transition hover:opacity-90"
                    phx-click="approve-draft"
                    phx-value-id={draft.id}
                  >
                    Approve
                  </button>
                  <button
                    id={"observability-benchmark-draft-reject-#{draft.id}"}
                    type="button"
                    class="inline-flex items-center rounded-lg border bg-muted px-3 py-1.5 text-sm font-semibold text-foreground transition hover:opacity-90"
                    phx-click="reject-draft"
                    phx-value-id={draft.id}
                  >
                    Reject
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </section>
    """
  end

  defp status_pill_class("approved"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp status_pill_class("rejected"),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp status_pill_class(_),
    do:
      "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ring-1 bg-muted text-foreground ring-border"

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
