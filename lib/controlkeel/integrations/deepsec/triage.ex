defmodule ControlKeel.Integrations.Deepsec.Triage do
  @moduledoc """
  Triage support for deepsec findings (P0/P1/P2 classification).

  This module provides triaging capabilities to classify findings
  by priority levels (P0, P1, P2) based on severity, exploitability,
  and other factors.
  """

  @doc """
  Classifies a finding by priority level (P0, P1, P2, P3).

  ## Parameters
  - finding: Finding to classify
  - opts: Keyword list of options
    - strict_mode: Use strict classification (default: false)

  ## Returns
  Priority level (:p0, :p1, :p2, :p3)
  """
  def classify_priority(finding, opts \\ []) do
    severity = Map.get(finding, "severity") || Map.get(finding, :severity) || "medium"

    exploitability =
      Map.get(finding, "exploitability_status") || Map.get(finding, :exploitability_status) ||
        "unknown"

    cwe_ids = Map.get(finding, "cwe_ids") || Map.get(finding, :cwe_ids) || []

    strict_mode = Keyword.get(opts, :strict_mode, false)

    cond do
      is_p0?(severity, exploitability, cwe_ids, strict_mode) ->
        :p0

      is_p1?(severity, exploitability, cwe_ids, strict_mode) ->
        :p1

      is_p2?(severity, exploitability, cwe_ids, strict_mode) ->
        :p2

      true ->
        :p3
    end
  end

  @doc """
  Classifies a list of findings by priority level.

  ## Parameters
  - findings: List of findings to classify
  - opts: Keyword list of options (same as classify_priority/2)

  ## Returns
  Map of priority levels to lists of findings
  """
  def classify_findings(findings, opts \\ []) when is_list(findings) do
    Enum.reduce(findings, %{p0: [], p1: [], p2: [], p3: []}, fn finding, acc ->
      priority = classify_priority(finding, opts)
      Map.update!(acc, priority, &[finding | &1])
    end)
    |> Map.new(fn {k, v} -> {k, Enum.reverse(v)} end)
  end

  @doc """
  Gets the priority label for a priority level.
  """
  def priority_label(:p0), do: "P0 - Critical"
  def priority_label(:p1), do: "P1 - High"
  def priority_label(:p2), do: "P2 - Medium"
  def priority_label(:p3), do: "P3 - Low"
  def priority_label(_), do: "Unknown"

  @doc """
  Gets the priority score for a priority level (higher = more severe).
  """
  def priority_score(:p0), do: 100
  def priority_score(:p1), do: 75
  def priority_score(:p2), do: 50
  def priority_score(:p3), do: 25
  def priority_score(_), do: 0

  @doc """
  Filters findings by priority level.
  """
  def filter_by_priority(findings, priority) when is_list(findings) do
    Enum.filter(findings, fn finding ->
      classify_priority(finding) == priority
    end)
  end

  @doc """
  Gets a summary of findings by priority.
  """
  def priority_summary(findings) when is_list(findings) do
    classified = classify_findings(findings)

    %{
      p0: length(classified.p0),
      p1: length(classified.p1),
      p2: length(classified.p2),
      p3: length(classified.p3),
      total: length(findings)
    }
  end

  @doc """
  Sorts findings by priority (P0 first, then P1, P2, P3).
  """
  def sort_by_priority(findings) when is_list(findings) do
    Enum.sort_by(findings, fn finding ->
      priority = classify_priority(finding)
      # Sort by priority score (descending)
      -priority_score(priority)
    end)
  end

  @doc """
  Gets the top N findings by priority.
  """
  def top_findings(findings, n \\ 10) when is_list(findings) do
    findings
    |> sort_by_priority()
    |> Enum.take(n)
  end

  @doc """
  Checks if a finding should block based on priority.

  ## Parameters
  - finding: Finding to check
  - opts: Keyword list of options
    - block_p0: Block P0 findings (default: true)
    - block_p1: Block P1 findings (default: false)
    - block_p2: Block P2 findings (default: false)

  ## Returns
  true if the finding should block, false otherwise
  """
  def should_block?(finding, opts \\ []) do
    priority = classify_priority(finding)

    block_p0 = Keyword.get(opts, :block_p0, true)
    block_p1 = Keyword.get(opts, :block_p1, false)
    block_p2 = Keyword.get(opts, :block_p2, false)

    case priority do
      :p0 -> block_p0
      :p1 -> block_p1
      :p2 -> block_p2
      :p3 -> false
    end
  end

  @doc """
  Converts priority to ControlKeel decision.
  """
  def priority_to_decision(:p0), do: "block"
  def priority_to_decision(:p1), do: "warn"
  def priority_to_decision(:p2), do: "warn"
  def priority_to_decision(:p3), do: "allow"
  def priority_to_decision(_), do: "warn"

  ## Private Functions

  defp is_p0?(severity, exploitability, cwe_ids, strict_mode) do
    # P0: Critical severity OR High severity with known exploit OR Critical CWE
    severity == "critical" or
      (severity == "high" and exploitability == "exploitable") or
      has_critical_cwe?(cwe_ids) or
      (strict_mode and severity == "high")
  end

  defp is_p1?(severity, exploitability, cwe_ids, strict_mode) do
    # P1: High severity OR Medium severity with known exploit OR High CWE
    severity == "high" or
      (severity == "medium" and exploitability == "exploitable") or
      has_high_cwe?(cwe_ids) or
      (strict_mode and severity == "medium")
  end

  defp is_p2?(severity, exploitability, cwe_ids, _strict_mode) do
    # P2: Medium severity OR Low severity with known exploit OR Medium CWE
    severity == "medium" or
      (severity == "low" and exploitability == "exploitable") or
      has_medium_cwe?(cwe_ids)
  end

  defp has_critical_cwe?(cwe_ids) do
    critical_cwes = [
      # OS Command Injection
      78,
      # SQL Injection
      89,
      # Code Injection
      94,
      # Buffer Overflow
      119,
      # Deserialization of Untrusted Data
      502,
      # Out-of-bounds Write
      787
    ]

    Enum.any?(cwe_ids, fn cwe_id ->
      cwe_id in critical_cwes
    end)
  end

  defp has_high_cwe?(cwe_ids) do
    high_cwes = [
      # Information Exposure
      20,
      # Path Traversal
      22,
      # XSS
      79,
      # Information Exposure
      200,
      # CSRF
      352,
      # DoS
      400,
      # Allocation of Resources Without Limits
      770
    ]

    Enum.any?(cwe_ids, fn cwe_id ->
      cwe_id in high_cwes
    end)
  end

  defp has_medium_cwe?(cwe_ids) do
    medium_cwes = [
      # Information Exposure Through Debug Information
      215,
      # Improper Authentication
      287,
      # Missing Encryption of Sensitive Data
      311,
      # Inadequate Encryption Strength
      326,
      # Incorrect Permission Assignment
      732,
      # Use of Hard-coded Credentials
      798
    ]

    Enum.any?(cwe_ids, fn cwe_id ->
      cwe_id in medium_cwes
    end)
  end
end
