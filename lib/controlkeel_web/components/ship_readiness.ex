defmodule ControlKeelWeb.ShipReadiness do
  @moduledoc """
  Renders the per-session ship-readiness section: verdict, posture metrics,
  autonomy/outcome alignment, and agent completion breakdown.
  """
  use Phoenix.Component

  attr :verdict, :map, required: true
  attr :improvement_loop, :map, default: %{}
  attr :outcome_metrics, :map, required: true
  attr :autonomy_profile, :map, required: true
  attr :outcome_profile, :map, required: true
  attr :agent_outcomes, :list, default: []

  def ship_readiness(assigns) do
    ~H"""
    <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
      <div class="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-white/5">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
          Ship readiness
        </p>
        <span class={[
          "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em]",
          verdict_badge_class(@verdict.tone)
        ]}>
          {@verdict.label}
        </span>
      </div>

      <p class="text-sm text-zinc-400 mt-4">
        {get_in(@improvement_loop || %{}, ["bottleneck_summary", "recommendation"])}
      </p>
      <p class="text-xs text-zinc-500 mt-1">
        Next: {get_in(@improvement_loop || %{}, ["recommended_next_step"]) || "—"}
      </p>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mt-5">
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Proof-backed tasks
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.proof_backed_task_coverage_percent)}
          </strong>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Deploy-ready rate
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.deploy_ready_task_rate_percent)}
          </strong>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Cost / deploy-ready
          </p>
          <strong class="block mt-1">
            {format_cost(@outcome_metrics.cost_per_deploy_ready_task_cents)}
          </strong>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            First deploy-ready proof
          </p>
          <strong class="block mt-1">
            {format_duration(@outcome_metrics.average_time_to_first_deploy_ready_proof_seconds)}
          </strong>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Risky interventions
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.risky_intervention_rate_percent)}
          </strong>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Resume success
          </p>
          <strong class="block mt-1">
            {format_percent(@outcome_metrics.resume_success_rate_percent)}
          </strong>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-5">
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500 mb-2">
            Autonomy posture
          </p>
          <p class="text-sm text-zinc-200">{@autonomy_profile["label"]}</p>
          <p class="text-xs text-zinc-500 mt-1">
            {@autonomy_profile["human_role"]} · {@autonomy_profile["operator_posture"]}
          </p>
        </div>
        <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500 mb-2">
            Outcome alignment
          </p>
          <p class="text-sm text-zinc-200">
            {@outcome_profile["label"]} · {@outcome_profile["status"]}
          </p>
          <p class="text-xs text-zinc-500 mt-1 truncate">{@outcome_profile["target"]}</p>
        </div>
      </div>

      <%= if @agent_outcomes != [] do %>
        <div class="mt-5">
          <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-zinc-500 mb-2">
            Task completion by agent
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <%= for row <- @agent_outcomes do %>
              <div class="p-4 rounded-2xl border border-white/10 bg-white/[0.03]">
                <p class="text-sm font-semibold text-zinc-200">{row.agent}</p>
                <p class="text-xs text-zinc-500 mt-1">
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
    do: "bg-emerald-400/15 text-emerald-300 border-emerald-400/30"

  defp verdict_badge_class("blocked"),
    do: "bg-red-400/15 text-red-300 border-red-400/30"

  defp verdict_badge_class("progress"),
    do: "bg-blue-400/15 text-blue-300 border-blue-400/30"

  defp verdict_badge_class(_), do: "bg-amber-400/15 text-amber-300 border-amber-400/30"

  defp format_percent(nil), do: "Not enough data"
  defp format_percent(value), do: "#{value}%"

  defp format_cost(nil), do: "Not recorded"
  defp format_cost(cents), do: "$#{:erlang.float_to_binary(cents / 100, decimals: 2)}"

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"
end
