defmodule ControlKeel.Integrations.Deepsec.Adapter do
  @moduledoc """
  Adapter for converting deepsec findings to ControlKeel findings.

  This module provides functions to convert deepsec's finding format
  to ControlKeel's finding schema, enabling unified governance of
  security findings across both systems.
  """

  alias ControlKeel.Scanner.Finding
  alias ControlKeel.SecurityWorkflow

  @doc """
  Converts a deepsec finding to a ControlKeel Scanner.Finding.

  ## Parameters
  - deepsec_finding: A map representing a deepsec finding with the expected structure:
    - vulnSlug: The vulnerability slug/identifier
    - severity: The severity level (LOW, MEDIUM, HIGH, CRITICAL)
    - title: Human-readable title
    - description: Detailed description
    - filePath: Path to the affected file
    - codeSnippet: Relevant code snippet (optional)
    - recommendation: Fix recommendation (optional)
    - cweIds: List of CWE identifiers (optional)
    - revalidation: Revalidation verdict if present (optional)

  ## Returns
  A ControlKeel.Scanner.Finding struct or nil if conversion fails
  """
  def to_ck_finding(deepsec_finding, opts \\ []) do
    with {:ok, normalized} <- normalize_deepsec_finding(deepsec_finding),
         {:ok, ck_finding} <- build_ck_finding(normalized, opts) do
      ck_finding
    else
      _error -> nil
    end
  end

  @doc """
  Converts a list of deepsec findings to ControlKeel findings.

  ## Parameters
  - deepsec_findings: List of deepsec finding maps
  - opts: Optional parameters (same as to_ck_finding)

  ## Returns
  List of ControlKeel.Scanner.Finding structs
  """
  def to_ck_findings(deepsec_findings, opts \\ []) when is_list(deepsec_findings) do
    deepsec_findings
    |> Enum.map(&to_ck_finding(&1, opts))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Converts deepsec severity to ControlKeel severity.

  ## Mapping
  - LOW -> "low"
  - MEDIUM -> "medium"
  - HIGH -> "high"
  - CRITICAL -> "critical"
  """
  def map_severity("LOW"), do: "low"
  def map_severity("MEDIUM"), do: "medium"
  def map_severity("HIGH"), do: "high"
  def map_severity("CRITICAL"), do: "critical"
  def map_severity(_), do: "medium"

  # Private functions

  defp normalize_deepsec_finding(deepsec_finding) when is_map(deepsec_finding) do
    vuln_slug = Map.get(deepsec_finding, "vulnSlug") || Map.get(deepsec_finding, :vulnSlug)
    severity = Map.get(deepsec_finding, "severity") || Map.get(deepsec_finding, :severity)
    title = Map.get(deepsec_finding, "title") || Map.get(deepsec_finding, :title)

    description =
      Map.get(deepsec_finding, "description") || Map.get(deepsec_finding, :description)

    file_path = Map.get(deepsec_finding, "filePath") || Map.get(deepsec_finding, :filePath)

    code_snippet =
      Map.get(deepsec_finding, "codeSnippet") || Map.get(deepsec_finding, :codeSnippet)

    recommendation =
      Map.get(deepsec_finding, "recommendation") || Map.get(deepsec_finding, :recommendation)

    cwe_ids = Map.get(deepsec_finding, "cweIds") || Map.get(deepsec_finding, :cweIds, [])

    revalidation =
      Map.get(deepsec_finding, "revalidation") || Map.get(deepsec_finding, :revalidation)

    if is_nil(vuln_slug) or is_nil(severity) or is_nil(title) do
      {:error, :missing_required_fields}
    else
      {:ok,
       %{
         vuln_slug: vuln_slug,
         severity: severity,
         title: title,
         description: description,
         file_path: file_path,
         code_snippet: code_snippet,
         recommendation: recommendation,
         cwe_ids: List.wrap(cwe_ids),
         revalidation: revalidation
       }}
    end
  end

  defp normalize_deepsec_finding(_), do: {:error, :invalid_format}

  defp build_ck_finding(normalized, opts) do
    decision = determine_decision(normalized, opts)
    plain_message = build_plain_message(normalized)
    metadata = build_metadata(normalized, opts)

    finding = %Finding{
      id: generate_finding_id(normalized),
      severity: map_severity(normalized.severity),
      category: "security",
      rule_id: "deepsec.#{normalized.vuln_slug}",
      decision: decision,
      plain_message: plain_message,
      location: %{
        "path" => normalized.file_path || "unknown",
        "kind" => Keyword.get(opts, :kind, "code")
      },
      metadata: metadata
    }

    {:ok, finding}
  end

  defp determine_decision(normalized, opts) do
    # Check revalidation verdict if present
    if normalized.revalidation do
      case Map.get(normalized.revalidation, "verdict") do
        "false-positive" -> "allow"
        "fixed" -> "allow"
        "true-positive" -> "warn"
        "uncertain" -> "warn"
        _ -> "warn"
      end
    else
      # Default to warn for security findings unless explicitly configured
      if Keyword.get(opts, :block_on_security, false) do
        "block"
      else
        "warn"
      end
    end
  end

  defp build_plain_message(normalized) do
    base_message = "[deepsec] #{normalized.title}"

    description =
      if normalized.description do
        " #{normalized.description}"
      else
        ""
      end

    recommendation =
      if normalized.recommendation do
        " Recommendation: #{normalized.recommendation}"
      else
        ""
      end

    base_message <> description <> recommendation
  end

  defp build_metadata(normalized, opts) do
    base_metadata = %{
      "scanner" => "deepsec",
      "matcher" => "deepsec_integration",
      "vuln_slug" => normalized.vuln_slug,
      "original_severity" => normalized.severity,
      "deepsec_finding" => true
    }

    # Add optional fields
    base_metadata
    |> maybe_put("description", normalized.description)
    |> maybe_put("code_snippet", normalized.code_snippet)
    |> maybe_put("recommendation", normalized.recommendation)
    |> maybe_put("cwe_ids", normalized.cwe_ids)
    |> maybe_put("revalidation_verdict", get_in(normalized, [:revalidation, "verdict"]))
    |> maybe_put("session_id", Keyword.get(opts, :session_id))
    |> maybe_put("task_id", Keyword.get(opts, :task_id))
    |> SecurityWorkflow.ensure_vulnerability_metadata(%{
      affected_component: normalized.file_path || "unknown",
      evidence_type: "source",
      exploitability_status: exploitability_status(normalized),
      patch_status: patch_status(normalized),
      disclosure_status: "draft",
      cwe_ids: normalized.cwe_ids,
      maintainer_scope: Keyword.get(opts, :maintainer_scope, "first_party")
    })
  end

  defp exploitability_status(_normalized), do: "suspected"

  defp patch_status(normalized) do
    if normalized.revalidation do
      case Map.get(normalized.revalidation, "verdict") do
        "fixed" -> "merged"
        _ -> "none"
      end
    else
      "none"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp generate_finding_id(normalized) do
    seed = "deepsec:#{normalized.vuln_slug}:#{normalized.file_path}:#{normalized.title}"
    "ds_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end
end
