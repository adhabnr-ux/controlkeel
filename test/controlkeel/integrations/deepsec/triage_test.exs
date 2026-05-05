defmodule ControlKeel.Integrations.Deepsec.TriageTest do
  use ExUnit.Case

  alias ControlKeel.Integrations.Deepsec.Triage

  describe "classify_priority/2" do
    test "classifies critical severity as P0" do
      finding = %{"severity" => "critical"}
      assert :p0 = Triage.classify_priority(finding)
    end

    test "classifies high severity with exploitability as P0" do
      finding = %{
        "severity" => "high",
        "exploitability_status" => "exploitable"
      }

      assert :p0 = Triage.classify_priority(finding)
    end

    test "classifies high severity as P1" do
      finding = %{"severity" => "high"}
      assert :p1 = Triage.classify_priority(finding)
    end

    test "classifies medium severity as P2" do
      finding = %{"severity" => "medium"}
      assert :p2 = Triage.classify_priority(finding)
    end

    test "classifies low severity as P3" do
      finding = %{"severity" => "low"}
      assert :p3 = Triage.classify_priority(finding)
    end

    test "classifies findings with critical CWE as P0" do
      finding = %{
        "severity" => "medium",
        # OS Command Injection
        "cwe_ids" => [78]
      }

      assert :p0 = Triage.classify_priority(finding)
    end

    test "classifies findings with high CWE as P1" do
      finding = %{
        "severity" => "low",
        # XSS
        "cwe_ids" => [79]
      }

      assert :p1 = Triage.classify_priority(finding)
    end
  end

  describe "classify_findings/2" do
    test "classifies a list of findings by priority" do
      findings = [
        %{"severity" => "critical"},
        %{"severity" => "high"},
        %{"severity" => "medium"},
        %{"severity" => "low"}
      ]

      classified = Triage.classify_findings(findings)

      assert length(classified.p0) == 1
      assert length(classified.p1) == 1
      assert length(classified.p2) == 1
      assert length(classified.p3) == 1
    end
  end

  describe "priority_summary/1" do
    test "returns summary of findings by priority" do
      findings = [
        %{"severity" => "critical"},
        %{"severity" => "high"},
        %{"severity" => "medium"}
      ]

      summary = Triage.priority_summary(findings)

      assert summary.p0 == 1
      assert summary.p1 == 1
      assert summary.p2 == 1
      assert summary.p3 == 0
      assert summary.total == 3
    end
  end

  describe "sort_by_priority/1" do
    test "sorts findings by priority (P0 first)" do
      findings = [
        %{"severity" => "low"},
        %{"severity" => "critical"},
        %{"severity" => "medium"}
      ]

      sorted = Triage.sort_by_priority(findings)

      assert Triage.classify_priority(hd(sorted)) == :p0
      assert Triage.classify_priority(List.last(sorted)) == :p3
    end
  end

  describe "should_block?/2" do
    test "blocks P0 findings by default" do
      finding = %{"severity" => "critical"}
      assert true = Triage.should_block?(finding)
    end

    test "does not block P1 findings by default" do
      finding = %{"severity" => "high"}
      refute Triage.should_block?(finding)
    end

    test "blocks P1 findings when configured" do
      finding = %{"severity" => "high"}
      assert true = Triage.should_block?(finding, block_p1: true)
    end

    test "does not block P3 findings" do
      finding = %{"severity" => "low"}
      refute Triage.should_block?(finding)
    end
  end

  describe "priority_to_decision/1" do
    test "converts P0 to block" do
      assert "block" = Triage.priority_to_decision(:p0)
    end

    test "converts P1 to warn" do
      assert "warn" = Triage.priority_to_decision(:p1)
    end

    test "converts P2 to warn" do
      assert "warn" = Triage.priority_to_decision(:p2)
    end

    test "converts P3 to allow" do
      assert "allow" = Triage.priority_to_decision(:p3)
    end
  end
end
