defmodule ControlKeelWeb.ObservabilityBenchmarkDraftsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    drafts = Observability.benchmark_drafts(opts)

    {:ok,
     socket
     |> assign(:page_title, "Benchmark Drafts")
     |> assign(:drafts, drafts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-benchmark-drafts-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Benchmark drafts</h1>
            <p class="ck-lead ck-lead-tight">
              Human-gated local benchmark draft scenarios generated from saved eval candidates.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-benchmark-drafts-count" class="ck-pill ck-pill-neutral">
              {@drafts.count} draft(s)
            </span>
            <.link navigate={~p"/observability/evals/persisted"} class="ck-link">Saved evals</.link>
            <.link navigate={~p"/observability/regressions"} class="ck-link">Regressions</.link>
            <.link navigate={~p"/benchmarks"} class="ck-link">Benchmarks</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-benchmark-drafts-status" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Status</p>
            <strong>{format_frequency(@drafts.by_status)}</strong>
          </div>
          <div id="observability-benchmark-drafts-suites" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Suites</p>
            <strong>{format_frequency(@drafts.by_suite)}</strong>
          </div>
        </div>

        <div id="observability-benchmark-drafts-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @drafts.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-benchmark-drafts-list" class="ck-card">
          <%= if @drafts.drafts == [] do %>
            <p class="ck-note">No benchmark drafts yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for draft <- @drafts.drafts do %>
                <li id={"observability-benchmark-draft-#{draft.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{draft.suite_slug}</p>
                      <strong>{draft.title}</strong>
                    </div>
                    <span class="ck-pill ck-pill-neutral">{draft.status}</span>
                  </div>
                  <p>{draft.scenario_prompt}</p>
                  <p class="ck-note">Expected: {draft.expected_behavior}</p>
                  <p class="ck-note">Human gate required: {draft.human_gate_required}</p>
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
    |> Enum.take(4)
    |> Enum.map(fn {key, count} -> "#{key}: #{count}" end)
    |> Enum.join(", ")
  end
end
