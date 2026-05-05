defmodule ControlKeel.Integrations.Deepsec.DedupTest do
  use ExUnit.Case

  alias ControlKeel.Integrations.Deepsec.Dedup

  describe "deduplicate_findings/2" do
    test "exact deduplication removes duplicates" do
      findings = [
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 10, "message" => "test"},
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 10, "message" => "test"},
        %{"rule_id" => "rule2", "filePath" => "file.ex", "line" => 20, "message" => "other"}
      ]

      deduplicated = Dedup.deduplicate_findings(findings, strategy: :exact)

      assert length(deduplicated) == 2
    end

    test "location deduplication removes same location duplicates" do
      findings = [
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 10, "message" => "test1"},
        %{"rule_id" => "rule2", "filePath" => "file.ex", "line" => 10, "message" => "test2"},
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 20, "message" => "other"}
      ]

      deduplicated = Dedup.deduplicate_findings(findings, strategy: :location)

      assert length(deduplicated) == 2
    end

    test "rule deduplication removes same rule duplicates" do
      findings = [
        %{"rule_id" => "rule1", "filePath" => "file1.ex", "line" => 10, "message" => "test1"},
        %{"rule_id" => "rule1", "filePath" => "file2.ex", "line" => 20, "message" => "test2"},
        %{"rule_id" => "rule2", "filePath" => "file3.ex", "line" => 30, "message" => "other"}
      ]

      deduplicated = Dedup.deduplicate_findings(findings, strategy: :rule)

      assert length(deduplicated) == 2
    end
  end

  describe "deduplicate_across_scans/3" do
    test "deduplicates new findings against previous findings" do
      previous = [
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 10, "message" => "test"}
      ]

      new = [
        %{"rule_id" => "rule1", "filePath" => "file.ex", "line" => 10, "message" => "test"},
        %{"rule_id" => "rule2", "filePath" => "file.ex", "line" => 20, "message" => "other"}
      ]

      {:ok, deduplicated, new_count} = Dedup.deduplicate_across_scans(new, previous)

      assert length(deduplicated) == 2
      assert new_count == 1
    end
  end

  describe "similarity/2" do
    test "calculates similarity between findings" do
      finding1 = %{"message" => "SQL injection vulnerability in user input"}
      finding2 = %{"message" => "SQL injection in user input"}

      similarity = Dedup.similarity(finding1, finding2)

      assert is_number(similarity)
      assert similarity > 0.5
    end

    test "returns 0 for completely different messages" do
      finding1 = %{"message" => "SQL injection"}
      finding2 = %{"message" => "XSS vulnerability"}

      similarity = Dedup.similarity(finding1, finding2)

      assert similarity < 0.5
    end
  end
end
