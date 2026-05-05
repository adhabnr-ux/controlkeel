defmodule ControlKeel.Integrations.Deepsec.Dedup do
  @moduledoc """
  Finding deduplication for deepsec scans.

  This module provides deduplication capabilities to avoid duplicate
  findings across multiple scans or from multiple sources.
  """

  @doc """
  Deduplicates a list of findings.

  ## Parameters
  - findings: List of findings to deduplicate
  - opts: Keyword list of options
    - strategy: Deduplication strategy (:exact, :similar, :location, :rule)
    - similarity_threshold: Threshold for similarity matching (0.0-1.0, default: 0.8)

  ## Returns
  Deduplicated list of findings
  """
  def deduplicate_findings(findings, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :exact)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, 0.8)

    case strategy do
      :exact -> exact_dedup(findings)
      :similar -> similar_dedup(findings, similarity_threshold)
      :location -> location_dedup(findings)
      :rule -> rule_dedup(findings)
      _ -> exact_dedup(findings)
    end
  end

  @doc """
  Deduplicates findings by exact match (all fields).
  """
  def exact_dedup(findings) do
    Enum.uniq_by(findings, &finding_signature/1)
  end

  @doc """
  Deduplicates findings by location (file path and line number).
  """
  def location_dedup(findings) do
    Enum.uniq_by(findings, &location_signature/1)
  end

  @doc """
  Deduplicates findings by rule ID.
  """
  def rule_dedup(findings) do
    Enum.uniq_by(findings, &rule_signature/1)
  end

  @doc """
  Deduplicates findings by similarity (content-based).

  This uses text similarity to group similar findings together.
  """
  def similar_dedup(findings, threshold \\ 0.8) do
    findings
    |> Enum.group_by(&rule_signature/1)
    |> Enum.flat_map(fn {_rule, group} ->
      # Group by location first
      by_location = Enum.group_by(group, &location_signature/1)

      # Then deduplicate similar findings within each location group
      Enum.flat_map(by_location, fn {_loc, location_group} ->
        deduplicate_similar_group(location_group, threshold)
      end)
    end)
  end

  @doc """
  Deduplicates findings across multiple scans.

  ## Parameters
  - new_findings: New findings from current scan
  - previous_findings: Findings from previous scan(s)
  - opts: Keyword list of options (same as deduplicate_findings/2)

  ## Returns
  {:ok, deduplicated_findings, new_findings_count} on success
  """
  def deduplicate_across_scans(new_findings, previous_findings, opts \\ []) do
    # Combine all findings
    all_findings = new_findings ++ previous_findings

    # Deduplicate
    deduplicated = deduplicate_findings(all_findings, opts)

    # Calculate how many are new
    new_count = length(deduplicated) - length(previous_findings)

    {:ok, deduplicated, max(new_count, 0)}
  end

  @doc """
  Generates a signature for a finding for exact deduplication.
  """
  def finding_signature(finding) when is_map(finding) do
    rule_id = Map.get(finding, "rule_id") || Map.get(finding, :rule_id) || "unknown"
    file_path = Map.get(finding, "filePath") || Map.get(finding, :file_path) || "unknown"
    line = Map.get(finding, "line") || Map.get(finding, :line) || 0
    message = Map.get(finding, "message") || Map.get(finding, :message) || ""

    :crypto.hash(:sha256, "#{rule_id}:#{file_path}:#{line}:#{message}")
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generates a location signature for a finding.
  """
  def location_signature(finding) when is_map(finding) do
    file_path = Map.get(finding, "filePath") || Map.get(finding, :file_path) || "unknown"
    line = Map.get(finding, "line") || Map.get(finding, :line) || 0

    "#{file_path}:#{line}"
  end

  @doc """
  Generates a rule signature for a finding.
  """
  def rule_signature(finding) when is_map(finding) do
    rule_id = Map.get(finding, "rule_id") || Map.get(finding, :rule_id) || "unknown"
    rule_id
  end

  @doc """
  Calculates similarity between two findings.

  Returns a value between 0.0 (completely different) and 1.0 (identical).
  """
  def similarity(finding1, finding2) do
    message1 = Map.get(finding1, "message") || Map.get(finding1, :message) || ""
    message2 = Map.get(finding2, "message") || Map.get(finding2, :message) || ""

    # Simple Jaccard similarity on words
    words1 = String.split(message1) |> MapSet.new()
    words2 = String.split(message2) |> MapSet.new()

    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()

    if union == 0 do
      0.0
    else
      intersection / union
    end
  end

  ## Private Functions

  defp deduplicate_similar_group(group, threshold) do
    # Sort by severity (keep highest severity)
    sorted = sort_by_severity(group)

    # Deduplicate by similarity
    deduplicated =
      Enum.reduce(sorted, [], fn finding, acc ->
        if Enum.any?(acc, fn existing -> similarity(finding, existing) >= threshold end) do
          # Similar to existing, skip
          acc
        else
          # Not similar, keep
          [finding | acc]
        end
      end)

    Enum.reverse(deduplicated)
  end

  defp sort_by_severity(findings) do
    severity_order = %{"critical" => 0, "high" => 1, "medium" => 2, "low" => 3}

    Enum.sort_by(findings, fn finding ->
      severity = Map.get(finding, "severity") || Map.get(finding, :severity) || "low"
      Map.get(severity_order, severity, 99)
    end)
  end
end
