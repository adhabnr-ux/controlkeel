defmodule ControlKeel.Cloud.ComplianceTemplateTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.ComplianceTemplate

  describe "render/2" do
    test "renders SOC 2 sections with evidence counts" do
      {:ok, template} = ComplianceTemplate.render(bundle(), "soc2")

      assert template["schema_version"] == "1"
      assert template["template"] == "soc2"
      assert template["title"] == "SOC 2"
      assert template["summary"]["findings"] == 2

      cc6 = section(template, "CC6")
      assert cc6["title"] == "Logical access controls"
      assert cc6["evidence_count"] == 3

      cc9 = section(template, "CC9")
      assert cc9["evidence_count"] == 2
      assert Enum.any?(cc9["evidence"], &(&1["rule_id"] == "security.test"))
    end

    test "renders GDPR sections with filtered security evidence" do
      {:ok, template} = ComplianceTemplate.render(bundle(), :gdpr)

      assert template["template"] == "gdpr"
      art32 = section(template, "Art.32")
      assert art32["title"] == "Security of processing"
      assert Enum.any?(art32["evidence"], &(&1["source"] == "findings" and &1["rule_id"] == "security.test"))
      refute Enum.any?(art32["evidence"], &(&1["rule_id"] == "cost.warn"))

      art33 = section(template, "Art.33")
      assert art33["evidence_count"] == 1
    end

    test "handles empty evidence sections" do
      empty = Map.merge(bundle(), %{
        "findings" => [],
        "reviews" => [],
        "review_audit_events" => [],
        "mcp_tool_calls" => [],
        "cloud_run_packages" => [],
        "received_telemetry_events" => []
      })

      {:ok, template} = ComplianceTemplate.render(empty, "soc2")
      assert Enum.all?(template["sections"], &(&1["evidence_count"] == 0))
    end

    test "renders EU AI Act sections with expected article ids" do
      {:ok, template} = ComplianceTemplate.render(bundle(), "eu_ai_act")

      assert template["template"] == "eu_ai_act"
      assert template["title"] == "EU AI Act (High-Risk)"

      ids = Enum.map(template["sections"], & &1["id"])
      assert "Art.9" in ids
      assert "Art.14" in ids
      assert "Art.17" in ids

      art14 = section(template, "Art.14")
      assert art14["title"] == "Human oversight"
      assert art14["evidence_count"] >= 1
      assert Enum.any?(art14["evidence"], &(&1["source"] == "reviews"))
    end

    test "EU AI Act Art.9 includes findings evidence" do
      {:ok, template} = ComplianceTemplate.render(bundle(), "eu_ai_act")
      art9 = section(template, "Art.9")
      assert art9["evidence_count"] >= 2
      assert Enum.any?(art9["evidence"], &(&1["rule_id"] == "security.test"))
    end

    test "renders NIST AI RMF sections with GOVERN/MAP/MEASURE/MANAGE" do
      {:ok, template} = ComplianceTemplate.render(bundle(), "nist_ai_rmf")

      assert template["template"] == "nist_ai_rmf"
      assert template["title"] == "NIST AI RMF"

      ids = Enum.map(template["sections"], & &1["id"])
      assert "GOVERN" in ids
      assert "MAP" in ids
      assert "MEASURE" in ids
      assert "MANAGE" in ids
    end

    test "NIST MAP section includes findings" do
      {:ok, template} = ComplianceTemplate.render(bundle(), "nist_ai_rmf")
      map_sec = section(template, "MAP")
      assert Enum.any?(map_sec["evidence"], &(&1["source"] == "findings"))
    end

    test "NIST MANAGE section only includes resolved findings" do
      bundle_with_resolved = put_in(bundle(), ["findings"], [
        %{"id" => 1, "category" => "security", "severity" => "high", "rule_id" => "s.1", "status" => "resolved", "inserted_at" => "2026-01-01T00:00:00Z"},
        %{"id" => 2, "category" => "cost", "severity" => "medium", "rule_id" => "c.1", "status" => "open", "inserted_at" => "2026-01-01T00:00:00Z"}
      ])

      {:ok, template} = ComplianceTemplate.render(bundle_with_resolved, "nist_ai_rmf")
      manage = section(template, "MANAGE")
      finding_evidence = Enum.filter(manage["evidence"], &(&1["source"] == "findings"))
      assert Enum.all?(finding_evidence, &(&1["rule_id"] == "s.1"))
    end

    test "supported_templates/0 includes all four frameworks" do
      supported = ComplianceTemplate.supported_templates()
      assert "soc2" in supported
      assert "gdpr" in supported
      assert "eu_ai_act" in supported
      assert "nist_ai_rmf" in supported
    end

    test "rejects unsupported templates" do
      assert {:error, :unsupported_template} = ComplianceTemplate.render(bundle(), "pci")
    end
  end

  defp section(template, id), do: Enum.find(template["sections"], &(&1["id"] == id))

  defp bundle do
    %{
      "schema_version" => "1",
      "generated_at" => "2026-01-01T00:00:00Z",
      "scope" => %{"type" => "workspace", "id" => 1},
      "window" => %{"since" => "2025-01-01T00:00:00Z", "until" => "2026-01-01T00:00:00Z"},
      "findings" => [
        %{"id" => 1, "category" => "security", "severity" => "high", "rule_id" => "security.test", "status" => "open", "inserted_at" => "2026-01-01T00:00:00Z"},
        %{"id" => 2, "category" => "cost", "severity" => "medium", "rule_id" => "cost.warn", "status" => "open", "inserted_at" => "2026-01-01T00:00:00Z"}
      ],
      "reviews" => [%{"id" => 10, "title" => "Plan", "status" => "approved", "inserted_at" => "2026-01-01T00:00:00Z"}],
      "review_audit_events" => [%{"id" => 11, "event_type" => "approved", "recorded_at" => "2026-01-01T00:00:00Z"}],
      "mcp_tool_calls" => [%{"id" => 12, "resource" => "mcp", "tool_name" => "search", "outcome" => "allowed", "requested_at" => "2026-01-01T00:00:00Z"}],
      "cloud_run_packages" => [%{"id" => 13, "runtime_target" => "devin", "status" => "completed", "inserted_at" => "2026-01-01T00:00:00Z"}],
      "received_telemetry_events" => [%{"id" => 14, "kind" => "finding", "received_at" => "2026-01-01T00:00:00Z"}]
    }
  end
end
