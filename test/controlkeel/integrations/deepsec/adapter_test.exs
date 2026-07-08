defmodule ControlKeel.Integrations.Deepsec.AdapterTest do
  use ControlKeel.DataCase

  alias ControlKeel.Integrations.Deepsec.Adapter
  alias ControlKeel.Scanner.Finding

  describe "to_ck_finding/1" do
    test "converts a valid deepsec finding to CK finding" do
      deepsec_finding = %{
        "vulnSlug" => "sql-injection",
        "severity" => "HIGH",
        "title" => "SQL Injection Vulnerability",
        "description" => "User input not sanitized in query",
        "filePath" => "app/models/user.ex",
        "codeSnippet" => "Repo.one(from u in User, where: u.id == ^user_input)",
        "recommendation" => "Use parameterized queries",
        "cweIds" => ["CWE-89"]
      }

      assert %Finding{} = ck_finding = Adapter.to_ck_finding(deepsec_finding)

      assert ck_finding.severity == "high"
      assert ck_finding.category == "security"
      assert ck_finding.rule_id == "deepsec.sql-injection"
      assert ck_finding.decision == "warn"
      assert ck_finding.plain_message =~ "SQL Injection Vulnerability"
      assert ck_finding.location["path"] == "app/models/user.ex"
      assert ck_finding.metadata["scanner"] == "deepsec"
      assert ck_finding.metadata["vuln_slug"] == "sql-injection"
      assert ck_finding.metadata["cwe_ids"] == ["CWE-89"]
    end

    test "maps severity levels correctly" do
      severities = [
        {"LOW", "low"},
        {"MEDIUM", "medium"},
        {"HIGH", "high"},
        {"CRITICAL", "critical"}
      ]

      Enum.each(severities, fn {deepsec_sev, ck_sev} ->
        finding = %{
          "vulnSlug" => "test-vuln",
          "severity" => deepsec_sev,
          "title" => "Test",
          "filePath" => "test.ex"
        }

        assert %Finding{severity: ^ck_sev} = Adapter.to_ck_finding(finding)
      end)
    end

    test "handles revalidation verdicts" do
      test_cases = [
        {%{"verdict" => "false-positive"}, "allow"},
        {%{"verdict" => "fixed"}, "allow"},
        {%{"verdict" => "true-positive"}, "warn"},
        {%{"verdict" => "uncertain"}, "warn"}
      ]

      Enum.each(test_cases, fn {revalidation, expected_decision} ->
        finding = %{
          "vulnSlug" => "test-vuln",
          "severity" => "HIGH",
          "title" => "Test",
          "filePath" => "test.ex",
          "revalidation" => revalidation
        }

        assert %Finding{decision: ^expected_decision} = Adapter.to_ck_finding(finding)
      end)
    end

    test "respects block_on_security option" do
      finding = %{
        "vulnSlug" => "test-vuln",
        "severity" => "HIGH",
        "title" => "Test",
        "filePath" => "test.ex"
      }

      assert %Finding{decision: "warn"} = Adapter.to_ck_finding(finding)
      assert %Finding{decision: "block"} = Adapter.to_ck_finding(finding, block_on_security: true)
    end

    test "returns nil for invalid input" do
      assert nil == Adapter.to_ck_finding(nil)
      assert nil == Adapter.to_ck_finding(%{})
      assert nil == Adapter.to_ck_finding("invalid")
    end

    test "returns nil for missing required fields" do
      assert nil == Adapter.to_ck_finding(%{"title" => "Test"})
      assert nil == Adapter.to_ck_finding(%{"severity" => "HIGH"})
      assert nil == Adapter.to_ck_finding(%{"vulnSlug" => "test"})
    end

    test "includes security workflow metadata" do
      finding = %{
        "vulnSlug" => "test-vuln",
        "severity" => "CRITICAL",
        "title" => "Test",
        "filePath" => "app/controllers/user.ex",
        "cweIds" => ["CWE-79"]
      }

      assert %Finding{metadata: metadata} = Adapter.to_ck_finding(finding)

      assert metadata["affected_component"] == "app/controllers/user.ex"
      assert metadata["evidence_type"] == "source"
      assert metadata["exploitability_status"] == "suspected"
      assert metadata["patch_status"] == "none"
      assert metadata["disclosure_status"] == "draft"
      assert metadata["cwe_ids"] == ["CWE-79"]
      assert metadata["maintainer_scope"] == "first_party"
    end
  end

  describe "to_ck_findings/1" do
    test "converts a list of deepsec findings" do
      findings = [
        %{
          "vulnSlug" => "sql-injection",
          "severity" => "HIGH",
          "title" => "SQL Injection",
          "filePath" => "app/models/user.ex"
        },
        %{
          "vulnSlug" => "xss",
          "severity" => "MEDIUM",
          "title" => "XSS Vulnerability",
          "filePath" => "app/views/index.html"
        }
      ]

      ck_findings = Adapter.to_ck_findings(findings)

      assert length(ck_findings) == 2
      assert Enum.all?(ck_findings, &is_struct(&1, Finding))
    end

    test "filters out nil conversions" do
      findings = [
        %{
          "vulnSlug" => "valid",
          "severity" => "HIGH",
          "title" => "Valid",
          "filePath" => "test.ex"
        },
        %{"invalid" => "finding"},
        nil
      ]

      ck_findings = Adapter.to_ck_findings(findings)

      assert length(ck_findings) == 1
    end
  end
end
