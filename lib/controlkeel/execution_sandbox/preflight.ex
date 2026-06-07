defmodule ControlKeel.ExecutionSandbox.Preflight do
  @moduledoc false

  alias ControlKeel.Mission

  @trust_boundary_rule_prefix "security.trust_boundary."

  @doc """
  Check trust boundary findings before sandbox execution.

  Returns `{:ok, :proceed}`, `{:error, {:blocked, reason, findings}}`, or
  `{:warn, message, findings}`.

  When `session_id` is `nil`, the check is skipped (backward compatible).
  """
  def check(session_id, requested_capabilities, opts \\ [])

  def check(nil, _requested_capabilities, _opts), do: {:ok, :proceed}

  def check(session_id, requested_capabilities, opts) do
    force = Keyword.get(opts, :force, false)
    findings = get_trust_boundary_findings(session_id, requested_capabilities)

    cond do
      has_critical?(findings) ->
        {:error, {:blocked, "Critical trust boundary findings prevent execution", findings}}

      has_high?(findings) and not force ->
        {:warn, "High trust boundary findings present. Use force: true to override.", findings}

      true ->
        {:ok, :proceed}
    end
  end

  defp get_trust_boundary_findings(session_id, requested_capabilities) do
    session_id
    |> Mission.list_session_findings()
    |> Enum.filter(&trust_boundary_finding?/1)
    |> Enum.filter(fn finding ->
      capabilities_overlap?(finding, requested_capabilities)
    end)
  end

  defp trust_boundary_finding?(%{rule_id: rule_id}) do
    String.starts_with?(rule_id, @trust_boundary_rule_prefix)
  end

  defp trust_boundary_finding?(_), do: false

  defp capabilities_overlap?(%{metadata: metadata}, requested_capabilities)
       when is_map(metadata) and is_list(requested_capabilities) do
    finding_caps =
      metadata
      |> Map.get("requested_capabilities", [])
      |> Kernel.||([])

    finding_caps == [] or Enum.any?(finding_caps, &(&1 in requested_capabilities))
  end

  defp capabilities_overlap?(_, []), do: true
  defp capabilities_overlap?(_, _), do: false

  defp has_critical?(findings), do: Enum.any?(findings, &(&1.severity == "critical"))
  defp has_high?(findings), do: Enum.any?(findings, &(&1.severity == "high"))
end
