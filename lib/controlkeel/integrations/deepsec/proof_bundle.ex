defmodule ControlKeel.Integrations.Deepsec.ProofBundle do
  @moduledoc """
  Proof bundle integration for deepsec scan results.

  This module wraps deepsec scan results in ControlKeel proof bundles,
  providing durable, auditable evidence of security scans.
  """

  alias ControlKeel.Mission
  alias ControlKeel.Integrations.Deepsec.Adapter

  @doc """
  Creates a proof bundle from deepsec scan results.

  ## Parameters
  - deepsec_results: Map containing deepsec scan results with keys:
    - findings: List of deepsec findings
    - scan_metadata: Map with scan metadata (timestamp, project_id, etc.)
    - metrics: Optional map with scan metrics (total_files, candidates, etc.)
  - session_id: ControlKeel session ID
  - task_id: ControlKeel task ID

  ## Returns
  {:ok, proof_bundle} on success, {:error, reason} on failure
  """
  def create_from_scan(deepsec_results, session_id, task_id) do
    with {:ok, normalized} <- normalize_scan_results(deepsec_results),
         {:ok, ck_findings} <- convert_findings(normalized.findings, session_id, task_id),
         {:ok, bundle_data} <- build_bundle_data(normalized, ck_findings),
         {:ok, proof_bundle} <- persist_proof_bundle(bundle_data, session_id, task_id) do
      {:ok, proof_bundle}
    else
      error -> error
    end
  end

  @doc """
  Updates an existing proof bundle with new deepsec scan results.

  ## Parameters
  - proof_bundle_id: Existing proof bundle ID
  - deepsec_results: New deepsec scan results
  - session_id: ControlKeel session ID
  - task_id: ControlKeel task ID

  ## Returns
  {:ok, updated_proof_bundle} on success, {:error, reason} on failure
  """
  def update_proof_bundle(proof_bundle_id, deepsec_results, session_id, task_id) do
    with {:ok, existing_bundle} <- Mission.get_proof_bundle(proof_bundle_id),
         {:ok, normalized} <- normalize_scan_results(deepsec_results),
         {:ok, ck_findings} <- convert_findings(normalized.findings, session_id, task_id),
         {:ok, bundle_data} <- build_bundle_data(normalized, ck_findings, existing_bundle),
         {:ok, updated_bundle} <-
           persist_proof_bundle(bundle_data, session_id, task_id, existing_bundle.version) do
      {:ok, updated_bundle}
    else
      error -> error
    end
  end

  @doc """
  Extracts security summary from a deepsec proof bundle.

  ## Parameters
  - proof_bundle: ControlKeel proof bundle struct or map

  ## Returns
  Map with security summary including:
  - total_findings: Total number of findings
  - critical_count: Number of critical findings
  - high_count: Number of high findings
  - medium_count: Number of medium findings
  - low_count: Number of low findings
  - revalidated_count: Number of revalidated findings
  - false_positive_count: Number of false positives
  """
  def security_summary(proof_bundle) do
    bundle =
      if is_map(proof_bundle) and Map.has_key?(proof_bundle, :bundle),
        do: proof_bundle.bundle,
        else: proof_bundle

    deepsec_data = get_in(bundle, ["deepsec_scan"]) || %{}
    findings = Map.get(deepsec_data, "findings", [])

    %{
      total_findings: length(findings),
      critical_count: count_by_severity(findings, "critical"),
      high_count: count_by_severity(findings, "high"),
      medium_count: count_by_severity(findings, "medium"),
      low_count: count_by_severity(findings, "low"),
      revalidated_count: count_revalidated(findings),
      false_positive_count: count_false_positives(findings)
    }
  end

  # Private functions

  defp normalize_scan_results(deepsec_results) when is_map(deepsec_results) do
    findings = Map.get(deepsec_results, "findings") || Map.get(deepsec_results, :findings, [])

    scan_metadata =
      Map.get(deepsec_results, "scan_metadata") || Map.get(deepsec_results, :scan_metadata, %{})

    metrics = Map.get(deepsec_results, "metrics") || Map.get(deepsec_results, :metrics, %{})

    # Ensure metadata has required fields
    scan_metadata =
      scan_metadata
      |> Map.put_new("scanned_at", DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put_new("project_id", "unknown")

    {:ok,
     %{
       findings: findings,
       scan_metadata: scan_metadata,
       metrics: metrics
     }}
  end

  defp normalize_scan_results(_), do: {:error, :invalid_format}

  defp convert_findings(deepsec_findings, session_id, task_id) do
    ck_findings =
      Adapter.to_ck_findings(deepsec_findings, session_id: session_id, task_id: task_id)

    {:ok, ck_findings}
  end

  defp build_bundle_data(normalized, ck_findings, existing_bundle \\ nil) do
    version = if existing_bundle, do: existing_bundle.version + 1, else: 1

    bundle_data = %{
      "deepsec_scan" => %{
        "findings" => Enum.map(ck_findings, &finding_to_map/1),
        "scan_metadata" => normalized.scan_metadata,
        "metrics" => normalized.metrics,
        "scanned_at" => normalized.scan_metadata["scanned_at"],
        "generated_by" => "deepsec_integration"
      },
      "security_summary" => %{
        "total_findings" => length(ck_findings),
        "by_severity" => group_findings_by_severity(ck_findings),
        "revalidated" => count_revalidated(normalized.findings),
        "false_positives" => count_false_positives(normalized.findings)
      },
      "version" => version,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, bundle_data}
  end

  defp persist_proof_bundle(bundle_data, session_id, task_id, version \\ 1) do
    # Calculate finding counts
    findings = get_in(bundle_data, ["deepsec_scan", "findings"]) || []
    open_count = count_by_decision(findings, "warn")
    blocked_count = count_by_decision(findings, "block")
    approved_count = count_by_decision(findings, "allow")

    # Calculate risk score (simple heuristic)
    risk_score = calculate_risk_score(findings)

    # Determine deploy readiness
    deploy_ready = risk_score < 0.7 and blocked_count == 0

    proof_bundle_attrs = %{
      session_id: session_id,
      task_id: task_id,
      version: version,
      status: "complete",
      risk_score: risk_score,
      deploy_ready: deploy_ready,
      open_findings_count: open_count,
      blocked_findings_count: blocked_count,
      approved_findings_count: approved_count,
      bundle: bundle_data,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case Mission.generate_proof_bundle(proof_bundle_attrs) do
      {:ok, proof_bundle} -> {:ok, proof_bundle}
      error -> error
    end
  end

  defp finding_to_map(%ControlKeel.Scanner.Finding{} = finding) do
    %{
      "id" => finding.id,
      "severity" => finding.severity,
      "category" => finding.category,
      "rule_id" => finding.rule_id,
      "decision" => finding.decision,
      "plain_message" => finding.plain_message,
      "location" => finding.location,
      "metadata" => finding.metadata
    }
  end

  defp finding_to_map(finding) when is_map(finding), do: finding

  defp group_findings_by_severity(findings) do
    findings
    |> Enum.group_by(& &1.severity)
    |> Enum.map(fn {severity, items} -> {severity, length(items)} end)
    |> Map.new()
  end

  defp count_by_severity(findings, severity) do
    findings
    |> Enum.filter(fn f ->
      f_severity = if is_map(f), do: Map.get(f, "severity"), else: f.severity
      f_severity == severity
    end)
    |> length()
  end

  defp count_by_decision(findings, decision) do
    findings
    |> Enum.filter(fn f ->
      f_decision = if is_map(f), do: Map.get(f, "decision"), else: f.decision
      f_decision == decision
    end)
    |> length()
  end

  defp count_revalidated(findings) do
    findings
    |> Enum.filter(fn f ->
      revalidation =
        if is_map(f),
          do: Map.get(f, "revalidation"),
          else: get_in(f.metadata, ["revalidation_verdict"])

      not is_nil(revalidation)
    end)
    |> length()
  end

  defp count_false_positives(findings) do
    findings
    |> Enum.filter(fn f ->
      verdict =
        if is_map(f),
          do: get_in(f, ["revalidation", "verdict"]),
          else: get_in(f.metadata, ["revalidation_verdict"])

      verdict == "false-positive"
    end)
    |> length()
  end

  defp calculate_risk_score(findings) do
    severity_weights = %{
      "critical" => 1.0,
      "high" => 0.7,
      "medium" => 0.4,
      "low" => 0.1
    }

    total_score =
      findings
      |> Enum.map(fn f ->
        severity = if is_map(f), do: Map.get(f, "severity"), else: f.severity
        Map.get(severity_weights, severity, 0.0)
      end)
      |> Enum.sum()

    max_score = length(findings) * 1.0

    if max_score > 0, do: total_score / max_score, else: 0.0
  end
end
