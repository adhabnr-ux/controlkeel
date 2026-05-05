defmodule ControlKeel.Integrations.Deepsec do
  @moduledoc """
  Main integration module for deepsec.

  This module provides the primary API for integrating deepsec
  with ControlKeel, including functions to process deepsec findings,
  create proof bundles, and manage the integration lifecycle.
  """

  alias ControlKeel.Integrations.Deepsec.{Adapter, Config, ProofBundle}
  alias ControlKeel.Mission

  @doc """
  Processes deepsec findings and converts them to ControlKeel findings.

  ## Parameters
  - deepsec_findings: List of deepsec finding maps
  - opts: Optional parameters
    - session_id: ControlKeel session ID
    - task_id: ControlKeel task ID
    - block_on_security: Override config to block on security findings

  ## Returns
  List of ControlKeel.Scanner.Finding structs
  """
  def process_findings(deepsec_findings, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)

    block_on_security =
      Keyword.get(opts, :block_on_security, Config.block_on_security_findings?())

    Adapter.to_ck_findings(deepsec_findings,
      session_id: session_id,
      task_id: task_id,
      block_on_security: block_on_security
    )
  end

  @doc """
  Creates a proof bundle from deepsec scan results.

  ## Parameters
  - deepsec_results: Map containing deepsec scan results
  - session_id: ControlKeel session ID
  - task_id: ControlKeel task ID

  ## Returns
  {:ok, proof_bundle} on success, {:error, reason} on failure
  """
  def create_proof_bundle(deepsec_results, session_id, task_id) do
    ProofBundle.create_from_scan(deepsec_results, session_id, task_id)
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
    ProofBundle.update_proof_bundle(proof_bundle_id, deepsec_results, session_id, task_id)
  end

  @doc """
  Processes a complete deepsec scan workflow: findings + proof bundle.

  ## Parameters
  - deepsec_results: Map containing deepsec scan results
  - session_id: ControlKeel session ID
  - task_id: ControlKeel task ID
  - opts: Optional parameters
    - create_proof_bundle: Whether to create a proof bundle (default: from config)

  ## Returns
  {:ok, %{findings: [...], proof_bundle: proof_bundle | nil}} on success
  """
  def process_scan(deepsec_results, session_id, task_id, opts \\ []) do
    with {:ok, config_valid} <- validate_config(),
         true <- config_valid == :ok,
         findings when is_list(findings) <-
           process_findings(deepsec_results, session_id: session_id, task_id: task_id),
         {:ok, result} <-
           maybe_create_proof_bundle(deepsec_results, session_id, task_id, findings, opts) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_config}
    end
  end

  @doc """
  Checks if deepsec should be triggered based on budget and configuration.

  ## Parameters
  - session_id: ControlKeel session ID
  - severity: Severity level (:low, :medium, :high, :critical)

  ## Returns
  {:ok, true} if deepsec should be triggered
  {:ok, false} if deepsec should not be triggered
  {:error, reason} if there's an error checking
  """
  def should_trigger_deepsec?(session_id, severity \\ :medium) do
    with true <- Config.enabled?(),
         true <- severity_meets_threshold?(severity),
         {:ok, within_budget} <- check_budget(session_id) do
      {:ok, within_budget}
    else
      false -> {:ok, false}
      error -> error
    end
  end

  @doc """
  Returns the security summary from a deepsec proof bundle.

  ## Parameters
  - proof_bundle: ControlKeel proof bundle struct or map

  ## Returns
  Map with security summary
  """
  def security_summary(proof_bundle) do
    ProofBundle.security_summary(proof_bundle)
  end

  @doc """
  Returns the current configuration.
  """
  def config do
    Config.inspect_config()
  end

  @doc """
  Validates the deepsec configuration.
  """
  def validate_config do
    Config.validate_config()
  end

  # Private functions

  defp maybe_create_proof_bundle(deepsec_results, session_id, task_id, findings, opts) do
    create_bundle =
      Keyword.get(opts, :create_proof_bundle, Config.auto_create_proof_bundles?())

    if create_bundle do
      case create_proof_bundle(deepsec_results, session_id, task_id) do
        {:ok, proof_bundle} ->
          {:ok, %{findings: findings, proof_bundle: proof_bundle}}

        {:error, _reason} ->
          # If proof bundle creation fails, still return the findings
          {:ok, %{findings: findings, proof_bundle: nil}}
      end
    else
      {:ok, %{findings: findings, proof_bundle: nil}}
    end
  end

  defp severity_meets_threshold?(severity) do
    min_severity = Config.min_severity_for_investigation()
    severity_order = [:low, :medium, :high, :critical]

    min_index = Enum.find_index(severity_order, &(&1 == min_severity))
    severity_index = Enum.find_index(severity_order, &(&1 == severity))

    not is_nil(min_index) and not is_nil(severity_index) and severity_index >= min_index
  end

  defp check_budget(session_id) do
    max_budget = Config.max_scan_budget_cents()

    case Mission.get_session(session_id) do
      nil ->
        # No session means no budget constraint
        {:ok, true}

      session ->
        spent_cents = session.spent_cents || 0
        budget_cents = session.budget_cents || 0

        if budget_cents <= 0 do
          # No budget configured, allow
          {:ok, true}
        else
          # Check if adding max_scan_budget would exceed session budget
          remaining = budget_cents - spent_cents
          {:ok, remaining >= max_budget}
        end
    end
  end
end
