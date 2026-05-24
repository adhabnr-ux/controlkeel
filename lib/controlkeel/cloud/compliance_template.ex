defmodule ControlKeel.Cloud.ComplianceTemplate do
  @moduledoc """
  Maps audit-export bundles into procurement-friendly compliance templates.

  The raw `ControlKeel.Cloud.AuditExport` bundle remains the evidence source of
  truth. This module only groups that existing evidence into SOC 2 and GDPR
  sections with stable section identifiers, human-readable labels, counts, and
  compact evidence references.
  """

  @schema_version "1"
  @supported ~w(soc2 gdpr)

  @doc "Supported template identifiers."
  def supported_templates, do: @supported

  @doc "Render an audit bundle as a compliance template."
  @spec render(map(), String.t() | atom()) :: {:ok, map()} | {:error, :unsupported_template}
  def render(bundle, template) when is_map(bundle) do
    case normalize(template) do
      "soc2" -> {:ok, base(bundle, "soc2", "SOC 2") |> Map.put("sections", soc2_sections(bundle))}
      "gdpr" -> {:ok, base(bundle, "gdpr", "GDPR") |> Map.put("sections", gdpr_sections(bundle))}
      _ -> {:error, :unsupported_template}
    end
  end

  def render(_, _), do: {:error, :unsupported_template}

  defp normalize(template) when is_atom(template), do: template |> Atom.to_string() |> normalize()
  defp normalize(template) when is_binary(template), do: template |> String.downcase() |> String.trim()
  defp normalize(_), do: nil

  defp base(bundle, template, title) do
    %{
      "schema_version" => @schema_version,
      "template" => template,
      "title" => title,
      "source_schema_version" => bundle["schema_version"],
      "generated_at" => bundle["generated_at"],
      "scope" => bundle["scope"],
      "window" => bundle["window"],
      "summary" => summary(bundle)
    }
  end

  defp summary(bundle) do
    %{
      "findings" => count(bundle, "findings"),
      "reviews" => count(bundle, "reviews"),
      "review_audit_events" => count(bundle, "review_audit_events"),
      "mcp_tool_calls" => count(bundle, "mcp_tool_calls"),
      "cloud_run_packages" => count(bundle, "cloud_run_packages"),
      "received_telemetry_events" => count(bundle, "received_telemetry_events")
    }
  end

  defp soc2_sections(bundle) do
    [
      section("CC6", "Logical access controls", "SSO/RBAC review decisions, reviewer activity, and protocol access decisions.", [
        refs(bundle, "reviews"),
        refs(bundle, "review_audit_events"),
        refs(bundle, "mcp_tool_calls")
      ]),
      section("CC7", "System operations and monitoring", "Security/cost findings, cloud-agent lifecycle, and telemetry intake evidence.", [
        refs(bundle, "findings"),
        refs(bundle, "cloud_run_packages"),
        refs(bundle, "received_telemetry_events")
      ]),
      section("CC8", "Change management", "Review approvals and cloud-agent run evidence tied to governed changes.", [
        refs(bundle, "reviews"),
        refs(bundle, "review_audit_events"),
        refs(bundle, "cloud_run_packages")
      ]),
      section("CC9", "Risk mitigation", "Open and historical findings grouped as risk evidence.", [refs(bundle, "findings")])
    ]
  end

  defp gdpr_sections(bundle) do
    [
      section("Art.5", "Principles relating to processing", "Findings and telemetry metadata supporting minimisation, integrity, and accountability.", [
        refs(bundle, "findings"),
        refs(bundle, "received_telemetry_events")
      ]),
      section("Art.30", "Records of processing activities", "Workspace/org audit bundle sections that document governed processing activity.", [
        refs(bundle, "reviews"),
        refs(bundle, "review_audit_events"),
        refs(bundle, "mcp_tool_calls"),
        refs(bundle, "cloud_run_packages")
      ]),
      section("Art.32", "Security of processing", "Security findings, protocol access decisions, and review controls.", [
        filtered_refs(bundle, "findings", &security_finding?/1),
        refs(bundle, "mcp_tool_calls"),
        refs(bundle, "reviews")
      ]),
      section("Art.33", "Incident and breach notification readiness", "High and critical findings that may require operator review.", [
        filtered_refs(bundle, "findings", &high_or_critical?/1)
      ])
    ]
  end

  defp section(id, title, description, ref_groups) do
    evidence = ref_groups |> List.flatten() |> Enum.reject(&is_nil/1)

    %{
      "id" => id,
      "title" => title,
      "description" => description,
      "evidence_count" => length(evidence),
      "evidence" => evidence
    }
  end

  defp refs(bundle, key), do: filtered_refs(bundle, key, fn _ -> true end)

  defp filtered_refs(bundle, key, predicate) do
    bundle
    |> Map.get(key, [])
    |> Enum.filter(predicate)
    |> Enum.map(&ref(key, &1))
  end

  defp ref(source, %{"id" => id} = item) do
    %{
      "source" => source,
      "id" => id,
      "label" => label(source, item),
      "severity" => item["severity"],
      "status" => item["status"],
      "rule_id" => item["rule_id"],
      "timestamp" => item["inserted_at"] || item["recorded_at"] || item["requested_at"] || item["received_at"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp ref(source, item), do: %{"source" => source, "label" => inspect(item)}

  defp label("findings", item), do: item["rule_id"] || item["title"] || "finding"
  defp label("reviews", item), do: item["title"] || item["review_type"] || "review"
  defp label("review_audit_events", item), do: item["event_type"] || "review_audit_event"
  defp label("mcp_tool_calls", item), do: Enum.join([item["resource"], item["tool_name"]] |> Enum.reject(&is_nil/1), ":")
  defp label("cloud_run_packages", item), do: item["runtime_target"] || "cloud_run_package"
  defp label("received_telemetry_events", item), do: item["kind"] || item["event_id"] || "telemetry_event"
  defp label(_, _), do: "evidence"

  defp security_finding?(%{"category" => category}) when is_binary(category), do: String.contains?(String.downcase(category), "security")
  defp security_finding?(%{"rule_id" => rule_id}) when is_binary(rule_id), do: String.contains?(String.downcase(rule_id), "security")
  defp security_finding?(_), do: false

  defp high_or_critical?(%{"severity" => severity}) when severity in ["high", "critical"], do: true
  defp high_or_critical?(_), do: false

  defp count(bundle, key), do: bundle |> Map.get(key, []) |> length()
end
