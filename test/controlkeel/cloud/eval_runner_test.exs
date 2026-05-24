defmodule ControlKeel.Cloud.EvalRunnerTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.EvalRunner

  describe "list_suites/0" do
    test "includes governance-regression with at least one case" do
      [suite | _] = EvalRunner.list_suites()
      assert suite.slug == "governance-regression"
      assert suite.case_count > 0
      assert is_binary(suite.title)
      assert is_binary(suite.description)
    end
  end

  describe "get_suite/1" do
    test "returns a suite for a known slug" do
      assert {:ok, suite} = EvalRunner.get_suite("governance-regression")
      assert suite.slug == "governance-regression"
      assert is_list(suite.cases)
    end

    test "returns :not_found for an unknown slug" do
      assert :not_found = EvalRunner.get_suite("no-such-suite")
    end
  end

  describe "run/1" do
    test "returns :not_found for an unknown suite" do
      assert :not_found = EvalRunner.run("no-such-suite")
    end

    test "governance-regression passes against the live scanner" do
      assert {:ok, result} = EvalRunner.run("governance-regression")
      assert result.failed == 0
      assert result.total > 0
      assert result.passed == result.total
      assert Enum.all?(result.cases, &(&1.status == :pass))
    end

    test "captures rule ids fired per case" do
      {:ok, result} = EvalRunner.run("governance-regression")

      rm_rf_case = Enum.find(result.cases, &(&1.name == "rm -rf at root scope"))
      assert rm_rf_case
      assert "destructive.shell.rm_rf_repo_scope" in rm_rf_case.actual_rule_ids
      assert rm_rf_case.decision == "block"

      clean_case = Enum.find(result.cases, &(&1.name == "clean shell command"))
      assert clean_case
      assert clean_case.actual_rule_ids == []
      assert clean_case.decision == "allow"
    end
  end
end
