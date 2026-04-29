defmodule ControlKeelWeb.ObservabilityPersistedEvalsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    saved = Observability.saved_eval_candidates(opts)

    {:ok,
     socket
     |> assign(:page_title, "Saved Eval Candidates")
     |> assign(:saved, saved)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-persisted-evals-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Saved eval candidates</h1>
            <p class="ck-lead ck-lead-tight">
              Local, human-gated candidate records saved from grouped problem feedback loops.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-persisted-evals-count" class="ck-pill ck-pill-neutral">
              {@saved.count} saved
            </span>
            <.link navigate={~p"/observability/evals"} class="ck-link">Advisory evals</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="observability-persisted-evals-status" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Status</p>
            <strong>{format_frequency(@saved.by_status)}</strong>
          </div>
          <div id="observability-persisted-evals-priority" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Priority</p>
            <strong>{format_frequency(@saved.by_priority)}</strong>
          </div>
        </div>

        <div id="observability-persisted-evals-recommendations" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @saved.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-persisted-evals-list" class="ck-card">
          <%= if @saved.candidates == [] do %>
            <p class="ck-note">No saved eval candidates yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for candidate <- @saved.candidates do %>
                <li id={"observability-persisted-eval-#{candidate.id}"}>
                  <div class="ck-card-header">
                    <div>
                      <p class="ck-mini-label">{candidate.category || "uncategorized"}</p>
                      <strong>{candidate.title}</strong>
                    </div>
                    <span class="ck-pill ck-pill-neutral">{candidate.status}</span>
                  </div>
                  <p class="ck-note">
                    {candidate.rule_id} · {candidate.priority} · human gate {candidate.human_gate_required}
                  </p>
                  <p>{candidate.evidence_summary}</p>
                  <p class="ck-note">Next: {candidate.suggested_action}</p>
                  <p class="ck-note">Benchmark hint: {candidate.benchmark_hint || "none"}</p>
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
