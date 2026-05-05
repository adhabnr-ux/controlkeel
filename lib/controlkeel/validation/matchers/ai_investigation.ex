defmodule ControlKeel.Validation.Matchers.AIInvestigation do
  @moduledoc """
  AI-powered security investigation hook.

  This module provides integration with deepsec's AI investigation
  for enhanced security validation in the security domain.
  """

  alias ControlKeel.Integrations.Deepsec
  alias ControlKeel.Mission

  @doc """
  Checks if AI investigation should be triggered for the given context.

  ## Parameters
  - session_id: ControlKeel session ID
  - domain_pack: Domain pack (e.g., "security")
  - severity: Severity of the finding

  ## Returns
  {:ok, true} if AI investigation should be triggered
  {:ok, false} if it should not be triggered
  {:error, reason} if there's an error
  """
  def should_trigger?(session_id, domain_pack, severity \\ :medium) do
    with true <- ai_investigation_enabled?(),
         true <- security_domain?(domain_pack),
         true <- severity_meets_threshold?(severity),
         {:ok, within_budget} <- check_budget(session_id) do
      {:ok, within_budget}
    else
      false -> {:ok, false}
      error -> error
    end
  end

  @doc """
  Performs AI investigation for a given finding using deepsec CLI.

  This function calls deepsec's process command to perform AI investigation
  on the codebase and returns the findings.

  ## Parameters
  - content: The content to investigate (note: deepsec processes entire workspace)
  - file_path: Path to the file (for metadata)
  - session_id: Session ID
  - task_id: Task ID
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)

  ## Returns
  {:ok, investigation_result} or {:error, reason}
  """
  def investigate(content, file_path, session_id, task_id, opts \\ []) do
    alias ControlKeel.Integrations.Deepsec.CLI

    workspace_path =
      Keyword.get(
        opts,
        :workspace_path,
        Application.get_env(:controlkeel, :deepsec, [])
        |> Keyword.get(:workspace_path, ".deepsec")
      )

    # Run deepsec process command for AI investigation
    case CLI.process(workspace_path: workspace_path) do
      {:ok, output} ->
        # Parse the output to extract findings
        {:ok, findings} = parse_process_output(output)

        {:ok,
         %{
           findings: findings,
           metadata: %{
             investigation_type: "deepsec_ai",
             file_path: file_path,
             content_length: String.length(content),
             session_id: session_id,
             task_id: task_id,
             timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
             raw_output: output
           }
         }}

      {:error, reason} ->
        {:error, "Deepsec process failed: #{reason}"}
    end
  end

  @doc """
  Processes AI investigation results and converts them to CK findings.

  ## Parameters
  - investigation_result: Result from investigate/4
  - session_id: Session ID
  - task_id: Task ID

  ## Returns
  {:ok, findings} or {:error, reason}
  """
  def process_results(investigation_result, session_id, task_id) do
    case Map.get(investigation_result, :findings) || Map.get(investigation_result, "findings") do
      nil ->
        {:ok, []}

      findings when is_list(findings) ->
        # Convert deepsec findings to CK findings
        ck_findings =
          Deepsec.process_findings(findings,
            session_id: session_id,
            task_id: task_id
          )

        {:ok, ck_findings}

      _ ->
        {:error, :invalid_findings_format}
    end
  end

  # Private functions

  defp parse_process_output(output) do
    # Try to parse JSON output from deepsec
    # Deepsec outputs findings in JSON format
    try do
      # Look for JSON in the output
      json_pattern = ~r/\{[\s\S]*\}/

      case Regex.run(json_pattern, output) do
        [json_string] ->
          case Jason.decode(json_string) do
            {:ok, data} ->
              # Extract findings from the parsed data
              findings = Map.get(data, "findings", [])
              {:ok, findings}

            {:error, _} ->
              # If JSON parsing fails, try to extract findings from text
              extract_findings_from_text(output)
          end

        _ ->
          # No JSON found, try to extract from text
          extract_findings_from_text(output)
      end
    rescue
      _ ->
        # If parsing fails, return empty findings
        {:ok, []}
    end
  end

  defp extract_findings_from_text(output) do
    # Simple text-based extraction as fallback
    # Look for patterns that indicate findings
    lines = String.split(output, "\n")

    findings =
      lines
      |> Enum.filter(fn line ->
        String.contains?(line, "vulnerability") or String.contains?(line, "finding") or
          String.contains?(line, "issue")
      end)
      |> Enum.map(fn line ->
        %{
          "type" => "text_extracted",
          "message" => String.trim(line),
          "severity" => infer_severity(line)
        }
      end)

    {:ok, findings}
  end

  defp infer_severity(text) do
    cond do
      String.contains?(String.downcase(text), "critical") -> "critical"
      String.contains?(String.downcase(text), "high") -> "high"
      String.contains?(String.downcase(text), "medium") -> "medium"
      true -> "low"
    end
  end

  defp ai_investigation_enabled? do
    Application.get_env(:controlkeel, :ai_investigation, [])
    |> Keyword.get(:enabled, false)
  end

  defp security_domain?(domain_pack) do
    domain_pack in ["security", nil]
  end

  defp severity_meets_threshold?(severity) do
    min_severity =
      Application.get_env(:controlkeel, :ai_investigation, [])
      |> Keyword.get(:min_severity, :high)

    severity_order = [:low, :medium, :high, :critical]
    min_index = Enum.find_index(severity_order, &(&1 == min_severity))
    severity_index = Enum.find_index(severity_order, &(&1 == severity))

    not is_nil(min_index) and not is_nil(severity_index) and severity_index >= min_index
  end

  defp check_budget(session_id) do
    max_budget =
      Application.get_env(:controlkeel, :ai_investigation, [])
      # Default $50
      |> Keyword.get(:max_investigation_budget_cents, 5_000)

    case session_id do
      nil ->
        # No session means no budget constraint
        {:ok, true}

      _ ->
        case Mission.get_session(session_id) do
          nil ->
            # Session not found, no budget constraint
            {:ok, true}

          session ->
            spent_cents = session.spent_cents || 0
            budget_cents = session.budget_cents || 0

            if budget_cents <= 0 do
              # No budget configured, allow
              {:ok, true}
            else
              # Check if adding max_investigation_budget would exceed session budget
              remaining = budget_cents - spent_cents
              {:ok, remaining >= max_budget}
            end
        end
    end
  end
end
