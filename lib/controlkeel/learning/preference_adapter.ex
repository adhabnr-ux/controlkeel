defmodule ControlKeel.Learning.PreferenceAdapter do
  @moduledoc false

  alias ControlKeel.Learning.Stats
  alias ControlKeel.Memory
  alias ControlKeel.Mission

  def record_preference(session_id, opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    preferences = Keyword.get(opts, :preferences, %{})

    attrs = %{
      workspace_id: workspace_id,
      session_id: session_id,
      record_type: "decision",
      title: "User preference recorded",
      summary: "Recorded user preferences for future personalization",
      body: "User preference: #{inspect(preferences)}",
      tags: ["user_preference", "personalization"],
      source_type: "preference_adapter",
      source_id: "pref:#{session_id}:#{System.unique_integer([:positive])}",
      metadata: %{
        preferences: preferences,
        session_id: session_id,
        recorded_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    Memory.record(attrs)
  end

  def get_preferences(session_id) do
    case Memory.search("user preference", session_id: session_id, top_k: 50) do
      %{entries: entries} ->
        preferences =
          entries
          |> Enum.filter(fn e ->
            tags = Map.get(e, :tags, [])
            "user_preference" in tags
          end)
          |> Enum.map(fn e -> Map.get(e, :metadata, %{}) |> Map.get("preferences", %{}) end)
          |> Enum.reduce(%{}, fn pref, acc ->
            Map.merge(acc, pref, fn _k, _v1, v2 -> v2 end)
          end)

        review_patterns =
          case analyze_review_patterns(session_id) do
            {:ok, patterns} when map_size(patterns) > 0 -> patterns
            _ -> nil
          end

        preferences =
          if review_patterns, do: Map.put(preferences, "review_patterns", review_patterns), else: preferences

        {:ok, preferences}

      _ ->
        {:ok, %{}}
    end
  end

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

  def detect_preferences(session_id, _opts \\ []) do
    case Memory.search("task completion session:#{session_id}", top_k: 100) do
      %{entries: entries} ->
        detected = analyze_patterns(entries)
        {:ok, detected}

      _ ->
        {:ok, %{}}
    end
  end

  def apply_preferences_to_brief(brief, preferences) when is_map(brief) and is_map(preferences) do
    Enum.reduce(preferences, brief, fn {key, value}, acc ->
      case key do
        "preferred_stack" ->
          put_in(acc, ["stack"], value)

        "preferred_css_framework" ->
          put_in(acc, ["css_framework"], value)

        "preferred_language" ->
          put_in(acc, ["language"], value)

        "preferred_model" ->
          put_in(acc, ["model"], value)

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp analyze_patterns(entries) do
    technologies =
      entries
      |> Enum.flat_map(fn e ->
        Map.get(e, :metadata, %{})
        |> Map.get("technologies", [])
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_tech, count} -> count >= 2 end)
      |> Enum.sort_by(fn {_tech, count} -> count end, :desc)
      |> Enum.map(fn {tech, _count} -> tech end)

    css_framework =
      entries
      |> Enum.flat_map(fn e ->
        meta = Map.get(e, :metadata, %{})
        Map.get(meta, "css_framework", [])
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_fw, count} -> count >= 2 end)
      |> Enum.sort_by(fn {_fw, count} -> count end, :desc)
      |> Enum.map(fn {fw, _count} -> fw end)
      |> List.first()

    detected = %{}

    detected =
      if length(technologies) > 0 do
        Map.put(detected, "preferred_stack", Enum.take(technologies, 3))
      else
        detected
      end

    detected =
      if css_framework do
        Map.put(detected, "preferred_css_framework", css_framework)
      else
        detected
      end

    detected
  end
end
