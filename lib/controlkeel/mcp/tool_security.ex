defmodule ControlKeel.MCP.ToolSecurity do
  @moduledoc """
  Static metadata scanner for MCP tool-poisoning and prompt-injection signals.
  """

  @critical_patterns [
    {~r/ignore (all )?(previous|prior|system|developer) instructions/i,
     "metadata attempts to override higher-priority instructions"},
    {~r/(exfiltrate|send|upload).{0,80}(secret|credential|token|key|password)/i,
     "metadata steers credential exfiltration"},
    {~r/(ssh|id_rsa|\.env|aws_access_key|private key)/i,
     "metadata references sensitive local credentials"}
  ]

  @warning_patterns [
    {~r/(do not tell|hide this|invisible to the user|secret instruction)/i,
     "metadata contains hidden-instruction language"},
    {~r/(curl|wget|http[s]?:\/\/).{0,120}(token|key|secret|password|credential)/i,
     "metadata references outbound network transfer with credentials"},
    {~r/(rm -rf|delete all|drop table|format disk)/i, "metadata references destructive actions"}
  ]

  def scan_tool(tool) when is_map(tool) do
    text = metadata_text(tool)
    critical = scan_patterns(text, @critical_patterns, "critical")
    warnings = scan_patterns(text, @warning_patterns, "warning")
    encoded = encoded_payload_warnings(text)
    findings = critical ++ warnings ++ encoded
    capabilities = capability_labels(tool, text)

    %{
      "trust_level" => trust_level(findings, capabilities),
      "capability_labels" => capabilities,
      "warning_count" => length(findings),
      "warnings" => findings
    }
  end

  def scan_tools(tools) when is_list(tools) do
    reports = Enum.map(tools, &scan_tool/1)
    warnings = Enum.flat_map(reports, & &1["warnings"])

    %{
      "trust_level" => aggregate_trust(reports),
      "tool_count" => length(tools),
      "warning_count" => length(warnings),
      "warnings" => warnings
    }
  end

  defp metadata_text(tool) do
    [
      Map.get(tool, "name"),
      Map.get(tool, "description"),
      Jason.encode!(Map.get(tool, "input_schema") || Map.get(tool, "inputSchema") || %{})
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp scan_patterns(text, patterns, severity) do
    Enum.flat_map(patterns, fn {pattern, message} ->
      if Regex.match?(pattern, text) do
        [%{"severity" => severity, "message" => message}]
      else
        []
      end
    end)
  end

  defp encoded_payload_warnings(text) do
    Regex.scan(~r/[A-Za-z0-9+\/_-]{80,}={0,2}/, text)
    |> List.flatten()
    |> Enum.take(3)
    |> Enum.map(fn _ ->
      %{"severity" => "warning", "message" => "metadata contains long encoded-looking payload"}
    end)
  end

  defp capability_labels(tool, text) do
    schema = Map.get(tool, "input_schema") || Map.get(tool, "inputSchema") || %{}
    lowered = String.downcase(text)

    []
    |> maybe_label(
      String.contains?(lowered, ["delete", "write", "update", "create", "mutate"]),
      "write"
    )
    |> maybe_label(
      String.contains?(lowered, ["http", "url", "webhook", "download", "upload"]),
      "network"
    )
    |> maybe_label(
      String.contains?(lowered, ["file", "path", "directory", "read_file"]),
      "filesystem"
    )
    |> maybe_label(
      String.contains?(lowered, ["secret", "token", "password", "credential", "api_key"]),
      "secrets"
    )
    |> maybe_label(schema_requires_command?(schema), "shell")
    |> Enum.reverse()
  end

  defp maybe_label(labels, true, label), do: [label | labels]
  defp maybe_label(labels, false, _label), do: labels

  defp schema_requires_command?(schema) when is_map(schema) do
    schema
    |> Jason.encode!()
    |> String.downcase()
    |> String.contains?(["command", "shell", "bash", "exec"])
  end

  defp schema_requires_command?(_), do: false

  defp trust_level(findings, capabilities) do
    cond do
      Enum.any?(findings, &(&1["severity"] == "critical")) -> "blocked_metadata"
      "secrets" in capabilities and "network" in capabilities -> "high_risk"
      findings != [] -> "review_required"
      true -> "unverified"
    end
  end

  defp aggregate_trust(reports) do
    levels = Enum.map(reports, & &1["trust_level"])

    cond do
      "blocked_metadata" in levels -> "blocked_metadata"
      "high_risk" in levels -> "high_risk"
      "review_required" in levels -> "review_required"
      true -> "unverified"
    end
  end
end
