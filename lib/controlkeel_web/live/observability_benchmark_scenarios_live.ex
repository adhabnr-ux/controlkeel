defmodule ControlKeelWeb.ObservabilityBenchmarkScenariosLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []
    scenarios = Observability.observability_benchmark_scenarios(opts)
    run_preview = Observability.observability_benchmark_run_preview(opts)

    {:ok,
     socket
     |> assign(:page_title, "Observability Benchmark Scenarios")
     |> assign(:scenarios, scenarios)
     |> assign(:run_preview, run_preview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="observability-benchmark-scenarios-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Observability</p>
            <h1 class="ck-section-title">Materialized benchmark scenarios</h1>
            <p class="ck-lead ck-lead-tight">
              Local Benchmark.Scenario records generated from approved observability drafts.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span id="observability-benchmark-scenarios-count" class="ck-pill ck-pill-neutral">
              {@scenarios.count} scenario(s)
            </span>
            <.link navigate={~p"/observability/benchmarks/drafts"} class="ck-link">Drafts</.link>
            <.link navigate={~p"/observability/benchmarks/history"} class="ck-link">History</.link>
            <.link navigate={~p"/benchmarks"} class="ck-link">Benchmarks</.link>
            <.link navigate={~p"/observability"} class="ck-link">Overview</.link>
          </div>
        </div>

        <div id="observability-benchmark-scenarios-summary" class="ck-card">
          <p class="ck-mini-label">Recommendations</p>
          <ul class="ck-mini-list">
            <%= for recommendation <- @scenarios.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-benchmark-run-guidance" class="ck-card">
          <p class="ck-mini-label">Human-gated execution</p>
          <p class="ck-note">
            Benchmark execution is CLI-only. Review generated scenarios first, then run an explicit command.
          </p>
          <code class="ck-code">
            {@run_preview.command || "controlkeel obs benchmarks run --dry-run"}
          </code>
          <ul class="ck-mini-list">
            <%= for recommendation <- @run_preview.recommendations do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>

        <div id="observability-benchmark-scenarios-list" class="ck-card">
          <%= if @scenarios.scenarios == [] do %>
            <p class="ck-note">No materialized observability scenarios yet.</p>
          <% else %>
            <ul class="ck-mini-list">
              <%= for scenario <- @scenarios.scenarios do %>
                <li id={"observability-benchmark-scenario-#{scenario.id}"}>
                  <strong>{scenario.name}</strong>
                  <p class="ck-note">{scenario.suite_slug} · {scenario.slug} · {scenario.split}</p>
                  <p class="ck-note">Expected rules: {Enum.join(scenario.expected_rules, ", ")}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
