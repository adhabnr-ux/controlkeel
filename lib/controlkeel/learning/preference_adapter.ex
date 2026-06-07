defmodule ControlKeel.Learning.PreferenceAdapter do
  @moduledoc false

  alias ControlKeel.Learning.Stats
  alias ControlKeel.Mission

  @doc """
  Learn alignment signal from the operator's review decisions and finding triage.

  Returns a map with:
    - "avg_approved_body_length" — mean submission_body length across approved plans
    - "top_denial_rule_ids" — most common review denial rule_ids / categories
    - "escalated_finding_categories" — finding categories the human keeps open or escalates
    - "auto_closed_finding_categories" — finding categories the human dismisses quickly
    - "median_refinement_depth" — typical depth at which plans get approved
    - "sample_size" — how many decisions informed the analysis

  This is the durable alignment signal the goal #299 calls for: the system learns
  from what the human approves and denies, not from what they say they prefer.
  """
  def analyze_review_patterns(session_id) when is_integer(session_id) do
    reviews =
      try do
        Mission.list_reviews_for_session(session_id)
      rescue
        _ -> []
      end

    findings =
      try do
        Mission.list_session_findings(session_id, %{})
      rescue
        _ -> []
      end

    decided = Enum.filter(reviews, &(&1.status in ["approved", "denied"]))
    approved = Enum.filter(decided, &(&1.status == "approved"))
    denied = Enum.filter(decided, &(&1.status == "denied"))

    avg_approved_length =
      case approved do
        [] ->
          nil

        list ->
          total =
            list
            |> Enum.map(&String.length(&1.submission_body || ""))
            |> Enum.sum()

          div(total, length(list))
      end

    top_denial_rule_ids =
      denied
      |> Enum.flat_map(fn r ->
        meta = r.metadata || %{}

        [
          Map.get(meta, "denial_rule_id"),
          get_in(meta, ["plan_quality", "missing"]) || []
        ]
        |> List.flatten()
        |> Enum.reject(&(&1 in [nil, ""]))
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} -> %{"key" => k, "count" => v} end)

    median_depth =
      approved
      |> Enum.map(fn r -> get_in(r.metadata || %{}, ["plan_refinement", "depth"]) || 1 end)
      |> Stats.median()

    {escalated, auto_closed} = classify_finding_triage(findings)

    patterns =
      %{
        "avg_approved_body_length" => avg_approved_length,
        "top_denial_rule_ids" => top_denial_rule_ids,
        "escalated_finding_categories" => escalated,
        "auto_closed_finding_categories" => auto_closed,
        "median_refinement_depth" => median_depth,
        "sample_size" => length(decided)
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, [], 0] end)
      |> Map.new()

    {:ok, patterns}
  end

  def analyze_review_patterns(_), do: {:ok, %{}}

  defp classify_finding_triage(findings) do
    grouped = Enum.group_by(findings, fn f -> Map.get(f, :status, "open") end)

    escalated =
      (Map.get(grouped, "escalated", []) ++ Map.get(grouped, "open", []))
      |> Enum.map(fn f -> Map.get(f, :category) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} -> %{"category" => k, "count" => v} end)

    auto_closed =
      (Map.get(grouped, "dismissed", []) ++ Map.get(grouped, "auto_closed", []))
      |> Enum.map(fn f -> Map.get(f, :category) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_k, v} -> v end, :desc)
      |> Enum.take(5)
      |> Enum.map(fn {k, v} -> %{"category" => k, "count" => v} end)

    {escalated, auto_closed}
  end
end
