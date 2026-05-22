defmodule ControlKeel.Learning.EngineerMirror do
  @moduledoc """
  Composes a human-facing daily mirror of how the operator is steering this
  session: today's plans submitted, decisions taken, prompt-quality outcomes,
  and the top signal worth their attention.

  Read-only. Reuses existing primitives (Mission reviews, decision-hygiene
  findings, OutcomeTracker, PreferenceAdapter) — no new schema, no new state.

  The point is reflection, not gamification. The mirror surfaces one signal and
  one suggestion so the engineer can see their own pattern in a single glance.
  """

  alias ControlKeel.Learning.{OutcomeTracker, PreferenceAdapter, Stats}
  alias ControlKeel.Mission

  @doc """
  Build the mirror payload for `session_id`.

  Returns:

      %{
        "session_id" => integer,
        "today" => %{
          "plans_submitted" => integer,
          "first_pass_approvals" => integer,
          "denials" => integer,
          "outcomes" => [%{...}, ...]
        },
        "rolling_30d" => %{
          "first_pass_rate" => float (0.0–1.0),
          "median_refinement_depth" => float | nil,
          "outcome_breakdown" => %{outcome => count}
        },
        "review_patterns" => %{...} | nil,
        "top_signal" => string | nil,
        "one_suggestion" => string | nil
      }
  """
  def build(session_id) when is_integer(session_id) do
    reviews =
      try do
        Mission.list_reviews_for_session(session_id)
      rescue
        _ -> []
      end

    {day_start, day_end} = today_range()

    today_reviews =
      Enum.filter(reviews, fn r -> Stats.within?(r.inserted_at, day_start, day_end) end)

    decided_today = Enum.filter(today_reviews, &(&1.status in ["approved", "denied"]))

    first_pass_today =
      Enum.count(decided_today, fn r ->
        r.status == "approved" and
          (get_in(r.metadata || %{}, ["plan_refinement", "depth"]) || 1) <= 1
      end)

    denials_today = Enum.count(decided_today, &(&1.status == "denied"))

    session_outcomes =
      case OutcomeTracker.get_session_outcomes(session_id) do
        {:ok, outcomes} when is_list(outcomes) -> outcomes
        _ -> []
      end

    prompt_outcomes =
      Enum.filter(session_outcomes, fn o ->
        String.starts_with?(Map.get(o, "outcome", ""), "prompt_")
      end)

    review_patterns =
      case PreferenceAdapter.analyze_review_patterns(session_id) do
        {:ok, p} when map_size(p) > 0 -> p
        _ -> nil
      end

    rolling = rolling_summary(prompt_outcomes, review_patterns)

    sunk_cost_signal =
      sunk_cost_from_rolling(rolling) ||
        sunk_cost_top_signal(session_id)

    top_signal = sunk_cost_signal || rate_signal(rolling)
    one_suggestion = suggestion_for(top_signal, rolling, review_patterns)

    %{
      "session_id" => session_id,
      "today" => %{
        "plans_submitted" => length(today_reviews),
        "first_pass_approvals" => first_pass_today,
        "denials" => denials_today,
        "outcomes" => Enum.take(prompt_outcomes_today(prompt_outcomes, {day_start, day_end}), 10)
      },
      "rolling_30d" => rolling,
      "review_patterns" => review_patterns,
      "top_signal" => top_signal,
      "one_suggestion" => one_suggestion
    }
  end

  def build(_), do: %{"error" => "session_id required"}

  defp rolling_summary(prompt_outcomes, review_patterns) do
    cutoff = Stats.ago(30 * 86_400)

    in_window =
      Enum.filter(prompt_outcomes, fn o ->
        Stats.at_or_after?(Map.get(o, "recorded_at"), cutoff)
      end)

    breakdown =
      in_window
      |> Enum.group_by(fn o -> Map.get(o, "outcome", "unknown") end)
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Map.new()

    first_pass = Map.get(breakdown, "prompt_first_pass", 0)
    total = Enum.sum(Map.values(breakdown))

    first_pass_rate =
      if total > 0 do
        Float.round(first_pass / total, 2)
      else
        nil
      end

    median_depth =
      case review_patterns do
        %{"median_refinement_depth" => v} -> v
        _ -> nil
      end

    %{
      "first_pass_rate" => first_pass_rate,
      "median_refinement_depth" => median_depth,
      "outcome_breakdown" => breakdown,
      "total_prompt_outcomes" => total
    }
  end

  defp prompt_outcomes_today(outcomes, {day_start, day_end}) do
    Enum.filter(outcomes, fn o ->
      Stats.within?(Map.get(o, "recorded_at"), day_start, day_end)
    end)
  end

  defp sunk_cost_from_rolling(%{"median_refinement_depth" => depth})
       when is_number(depth) and depth >= 3 do
    "Sunk-cost signal: median refinement depth is #{depth}. " <>
      "Plans are being refined repeatedly before approval — consider approving, narrowing, or abandoning."
  end

  defp sunk_cost_from_rolling(_), do: nil

  defp sunk_cost_top_signal(session_id) do
    try do
      session_id
      |> Mission.list_session_findings(%{})
      |> Enum.filter(fn f ->
        category = Map.get(f, :category) || ""
        rule_id = Map.get(f, :rule_id) || ""
        status = Map.get(f, :status) || ""

        status in ["open", "escalated"] and
          (category == "decision-hygiene" or String.contains?(rule_id, "sunk_cost"))
      end)
      |> Enum.sort_by(fn f -> Map.get(f, :inserted_at) end, {:desc, NaiveDateTime})
      |> List.first()
      |> case do
        nil -> nil
        f -> Map.get(f, :plain_message) || Map.get(f, :title)
      end
    rescue
      _ -> nil
    end
  end

  defp rate_signal(%{"first_pass_rate" => rate}) when is_float(rate) do
    cond do
      rate >= 0.7 ->
        "Strong steering: #{trunc(rate * 100)}% of plans approved on first pass."

      rate >= 0.4 ->
        "Mixed steering: #{trunc(rate * 100)}% first-pass approval. Tighten scope before submitting."

      true ->
        "Low first-pass rate (#{trunc(rate * 100)}%). Plans are getting denied or refined repeatedly — consider smaller slices."
    end
  end

  defp rate_signal(_), do: nil

  defp suggestion_for(signal, rolling, _patterns) when is_binary(signal) do
    cond do
      String.contains?(signal, "Sunk-cost") or String.contains?(signal, "refined") ->
        "Approve, narrow, or abandon the current plan before opening a new one."

      Map.get(rolling, "first_pass_rate", 0.0) && Map.get(rolling, "first_pass_rate") < 0.5 ->
        "Try shorter plans with explicit validation steps — the median approved depth here is #{Map.get(rolling, "median_refinement_depth") || "unknown"}."

      true ->
        "Keep going — your steering pattern is consistent."
    end
  end

  defp suggestion_for(_signal, _rolling, _patterns), do: nil

  defp today_range do
    now = DateTime.utc_now()
    start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    {start, now}
  end
end
