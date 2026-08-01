defmodule ControlKeelWeb.ShipReadiness do
  @moduledoc """
  Renders the per-session ship-readiness section: verdict, posture metrics,
  autonomy/outcome alignment, and agent completion breakdown.
  """
  use Phoenix.Component

  import ControlKeelWeb.Typography

  attr :verdict, :map, required: true
  attr :improvement_loop, :map, default: %{}
  attr :outcome_metrics, :map, required: true
  attr :autonomy_profile, :map, required: true
  attr :outcome_profile, :map, required: true
  attr :agent_outcomes, :list, default: []

  def ship_readiness(assigns) do
    ~H"""
    <div class="rounded-2xl border bg-card p-6 shadow-card mt-6">
      <div class="flex flex-wrap items-center justify-between gap-3 pb-4 border-b">
        <.section_title>Ship readiness</.section_title>

        <span class={[
          "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em]",
          verdict_badge_class(@verdict.tone)
        ]}>
          {@verdict.label}
        </span>
      </div>

      <p class="text-sm text-muted-foreground mt-4">
        {get_in(@improvement_loop || %{}, ["bottleneck_summary", "recommendation"])}
      </p>
      <p class="text-xs text-muted-foreground mt-1">
        Next: {get_in(@improvement_loop || %{}, ["recommended_next_step"]) || "—"}
      </p>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mt-5">
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Proof-backed tasks
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.proof_backed_task_coverage_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Deploy-ready rate
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.deploy_ready_task_rate_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Cost / deploy-ready
          </p>
          <strong class="block mt-1">
            {format_cost(@outcome_metrics.cost_per_deploy_ready_task_cents)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            First deploy-ready proof
          </p>
          <strong class="block mt-1">
            {format_duration(@outcome_metrics.average_time_to_first_deploy_ready_proof_seconds)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Risky interventions
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.risky_intervention_rate_percent)}
          </strong>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            Resume success
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.resume_success_rate_percent)}
          </strong>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-5">
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Autonomy posture
          </p>
          <p class="text-sm text-foreground">{@autonomy_profile["label"]}</p>
          <p class="text-xs text-muted-foreground mt-1">
            {@autonomy_profile["human_role"]} · {@autonomy_profile["operator_posture"]}
          </p>
        </div>
        <div class="rounded-2xl bg-muted p-4">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Outcome alignment
          </p>
          <p class="text-sm text-foreground">
            {@outcome_profile["label"]} · {@outcome_profile["status"]}
          </p>
          <p class="text-xs text-muted-foreground mt-1 truncate">{@outcome_profile["target"]}</p>
        </div>
      </div>

      <%= if @agent_outcomes != [] do %>
        <div class="mt-5">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-muted-foreground mb-2">
            Task completion by agent
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <%= for row <- @agent_outcomes do %>
              <div class="rounded-2xl bg-muted p-4">
                <p class="text-sm font-semibold text-foreground">{row.agent}</p>
                <p class="text-xs text-muted-foreground mt-1">
                  {row.completed_tasks}/{row.total_tasks} done · {format_percent(
                    row.completion_rate_percent
                  )} · {row.deploy_ready_tasks} deploy-ready
                </p>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp verdict_badge_class("ready"),
    do: "bg-success/15 text-success border-success/30"

  defp verdict_badge_class("blocked"),
    do: "bg-destructive/15 text-destructive border-destructive/30"

  defp verdict_badge_class("progress"),
    do: "bg-info/15 text-info border-info/30"

  defp verdict_badge_class(_),
    do: "bg-warning/15 text-warning border-warning/30"

  defp format_percent(nil), do: "Not enough data"
  defp format_percent(value), do: "#{value}%"

  defp format_cost(nil), do: "Not recorded"
  defp format_cost(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"
end
