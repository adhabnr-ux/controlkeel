defmodule ControlKeelWeb.ObservabilityProblemsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeel.Observability

  @impl true
  def mount(_params, _session, socket) do
    recent_session = Mission.list_recent_sessions(1) |> List.first()
    opts = if recent_session, do: [workspace_id: recent_session.workspace_id], else: []

    {:ok,
     socket
     |> assign(:page_title, "Observability Problems")
     |> assign(:problems, Observability.problems(opts))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section
        id="observability-problem-list"
        class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 space-y-5"
      >
        <p class="text-xs font-semibold tracking-[0.14em] uppercase text-[var(--ck-lime)] mb-6">
          Problems
        </p>

        <div class="space-y-8">
          <div>
            <span class="inline-flex items-center border border-[var(--ck-stroke)] rounded-full px-3 py-1.5 text-sm bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {@problems.count} {if @problems.count == 1, do: "group", else: "groups"}
            </span>

            <span class={health_pill_class(@problems.health)}>{@problems.health}</span>
          </div>

          <%= if @problems.recommendations != [] do %>
            <div class="space-y-2">
              <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
                Recommendations
              </p>
              <%= for recommendation <- @problems.recommendations do %>
                <p class="text-[var(--ck-text)] text-sm leading-relaxed">
                  {recommendation}
                </p>
              <% end %>
            </div>
          <% end %>

          <%= if @problems.problems == [] do %>
            <p class="text-[var(--ck-muted)] text-sm">No active problems detected.</p>
          <% else %>
            <%= for {problem, idx} <- Enum.with_index(@problems.problems) do %>
              <div
                id={"observability-problem-#{problem_key_id(problem.key)}"}
                class={["space-y-8", if(idx > 0, do: "pt-8 border-t border-[var(--ck-stroke)]")]}
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="space-y-1 min-w-0">
                    <p class="text-xl font-semibold text-[var(--ck-text)]">
                      {problem.title}
                    </p>
                  </div>
                  <span class={health_pill_class(problem.health)}>{problem.health}</span>
                </div>

                <div>
                  <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Category
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">{problem.category}</p>
                    </div>
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Rule ID
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">{problem.rule_id}</p>
                    </div>
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Severity
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">{problem.severity}</p>
                    </div>
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Count
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">{problem.count}</p>
                    </div>
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Sessions
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">
                        {problem.affected_session_count}
                      </p>
                    </div>
                    <div class="col-span-2 md:col-span-3">
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Last seen
                      </p>
                      <p class="text-[var(--ck-text)] mt-1 font-medium">
                        {format_datetime(problem.last_seen)}
                      </p>
                    </div>
                    <div class="col-span-2 md:col-span-4 mt-2">
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Recommendation
                      </p>
                      <p class="text-[var(--ck-text)] mt-1.5 leading-relaxed">
                        {problem.recommendation}
                      </p>
                    </div>
                  </div>
                </div>

                <div class="space-y-3">
                  <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-muted)] font-semibold">
                    Feedback loop
                  </p>
                  <div class="space-y-4">
                    <div class="flex flex-wrap gap-x-8 gap-y-4 text-sm">
                      <div>
                        <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                          Eval
                        </p>
                        <p class="text-[var(--ck-text)] mt-1 font-medium">
                          {problem.feedback_loop.eval_candidate_title}
                        </p>
                      </div>
                      <div>
                        <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                          Action
                        </p>
                        <p class="text-[var(--ck-text)] mt-1 font-medium">
                          {problem.feedback_loop.evidence_summary}
                        </p>
                      </div>
                      <div>
                        <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                          Benchmark
                        </p>
                        <p class="text-[var(--ck-text)] mt-1 font-medium">
                          {problem.feedback_loop.benchmark_hint}
                        </p>
                      </div>
                      <div>
                        <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                          Human Gate
                        </p>
                        <p class={[
                          "mt-1 font-medium",
                          if(problem.feedback_loop.human_gate_required,
                            do: "text-[#ffcf6b]",
                            else: "text-[var(--ck-text)]"
                          )
                        ]}>
                          {if problem.feedback_loop.human_gate_required do
                            "required"
                          else
                            "not required"
                          end}
                        </p>
                      </div>
                    </div>
                    <div>
                      <p class="text-[var(--ck-muted)] uppercase tracking-[0.1em] text-[10px]">
                        Suggested Action
                      </p>
                      <p class="text-[var(--ck-text)] text-sm mt-1.5">
                        {problem.feedback_loop.suggested_action}
                      </p>
                    </div>
                  </div>
                </div>

                <%= if problem.examples && problem.examples != [] do %>
                  <div class="space-y-3">
                    <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-muted)] font-semibold">
                      Examples
                    </p>
                    <div class="grid gap-2">
                      <%= for example <- problem.examples do %>
                        <div class="flex items-center justify-between gap-4 rounded-xl px-4 py-3 border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.015)] hover:bg-[rgba(255,255,255,0.03)] transition-colors">
                          <div class="min-w-0">
                            <p class="text-sm font-medium text-[var(--ck-text)] truncate">
                              {example.title}
                            </p>
                            <p class="text-xs text-[var(--ck-muted)] mt-1">
                              {example.severity} / {example.status}
                              <span class="mx-1.5 opacity-50">•</span> session {example.session_id}
                            </p>
                          </div>
                          <.link
                            navigate={~p"/observability/sessions/#{example.session_id}"}
                            class="shrink-0 text-sm text-[var(--ck-lime)] font-semibold hover:opacity-80 transition-opacity"
                          >
                            Open run →
                          </.link>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp health_pill_class("red"), do: "ck-pill ck-pill-critical"
  defp health_pill_class("yellow"), do: "ck-pill ck-pill-warning"
  defp health_pill_class(_), do: "ck-pill ck-pill-low"

  defp problem_key_id(key) do
    key
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
    |> String.trim("-")
  end

  defp format_datetime(nil), do: "unknown"
  defp format_datetime(""), do: "unknown"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> value
    end
  end

  defp format_datetime(value), do: to_string(value)
end
