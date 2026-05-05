defmodule ControlKeel.Validation.Matchers.ScannerTest do
  use ExUnit.Case

  alias ControlKeel.Validation.Matchers.{Matcher, Registry, Scanner}
  alias ControlKeel.Scanner.Finding

  setup do
    # Start the registry for each test
    start_supervised!(Registry)
    Registry.clear()
    :ok
  end

  describe "scan/3" do
    test "scans content and returns findings" do
      matcher = Matcher.new("test-slug", :precise, [".ex"], [~r/query_raw/], "Test matcher")
      Registry.register(matcher)

      content = "Repo.query_raw(query)"
      findings = Scanner.scan(content, "app/models/user.ex")

      assert is_list(findings)
      assert length(findings) > 0
      assert Enum.all?(findings, &is_struct(&1, Finding))
    end

    test "returns empty list when no matchers match" do
      matcher = Matcher.new("test-slug", :precise, [".js"], [~r/test/], "Test matcher")
      Registry.register(matcher)

      content = "safe elixir code"
      findings = Scanner.scan(content, "app/models/user.ex")

      assert findings == []
    end

    test "respects max_findings option" do
      matcher = Matcher.new("test-slug", :normal, [".ex"], [~r/test/], "Test matcher")
      Registry.register(matcher)

      content = String.duplicate("test ", 100)
      findings = Scanner.scan(content, "app/models/user.ex", max_findings: 5)

      assert length(findings) <= 5
    end

    test "includes session_id and task_id in metadata" do
      matcher = Matcher.new("test-slug", :precise, [".ex"], [~r/test/], "Test matcher")
      Registry.register(matcher)

      content = "test content"
      findings = Scanner.scan(content, "app/models/user.ex", session_id: 123, task_id: 456)

      assert length(findings) > 0
      assert hd(findings).metadata["session_id"] == 123
      assert hd(findings).metadata["task_id"] == 456
    end
  end

  describe "scan_with_matchers/4" do
    test "scans using specific matchers by slug" do
      matcher1 = Matcher.new("slug1", :precise, [".ex"], [~r/pattern1/], "Test 1")
      matcher2 = Matcher.new("slug2", :normal, [".ex"], [~r/pattern2/], "Test 2")

      Registry.register(matcher1)
      Registry.register(matcher2)

      content = "pattern1 here"
      findings = Scanner.scan_with_matchers(content, "test.ex", ["slug1"])

      assert length(findings) > 0
      assert hd(findings).metadata["matcher_slug"] == "slug1"
    end

    test "ignores non-existent matcher slugs" do
      matcher = Matcher.new("slug1", :precise, [".ex"], [~r/pattern/], "Test")
      Registry.register(matcher)

      content = "pattern here"
      findings = Scanner.scan_with_matchers(content, "test.ex", ["slug1", "non-existent"])

      assert length(findings) > 0
    end
  end

  describe "statistics/0" do
    test "returns matcher statistics" do
      matcher1 =
        Matcher.new("slug1", :precise, ["**/*.ex"], [~r/test/], "Test 1", category: "security")

      matcher2 =
        Matcher.new("slug2", :normal, ["**/*.js"], [~r/pattern/], "Test 2", category: "quality")

      Registry.register(matcher1)
      Registry.register(matcher2)

      stats = Scanner.statistics()

      assert stats.total_matchers == 2
      assert stats.by_tier[:precise] == 1
      assert stats.by_tier[:normal] == 1
      assert stats.by_category["security"] == 1
      assert stats.by_category["quality"] == 1
    end

    test "returns empty statistics when no matchers" do
      stats = Scanner.statistics()

      assert stats.total_matchers == 0
      assert stats.by_tier == %{}
      assert stats.by_category == %{}
    end
  end

  describe "deepsec_scan/1" do
    test "returns error when deepsec CLI is not available" do
      # Mock CLI.available? to return false
      # Note: This would require mocking the CLI module
      # For now, we'll just test the function signature
      # In a real test environment, we'd use Mox or similar

      # Skip this test if deepsec is actually available
      unless ControlKeel.Integrations.Deepsec.CLI.available?() do
        assert {:error, _reason} = Scanner.deepsec_scan([])
      end
    end

    test "accepts workspace_path option" do
      # Test that the function accepts the option
      # Actual execution requires deepsec to be installed
      tmp_dir = System.tmp_dir!()
      workspace_path = Path.join(tmp_dir, "test_workspace")

      # Just test that it doesn't crash on invalid input
      # (will fail with proper error about deepsec not being available)
      result = Scanner.deepsec_scan(workspace_path: workspace_path)

      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end

  describe "deepsec_full_scan/1" do
    test "accepts skip_revalidate option" do
      # Test that the function accepts the option
      result = Scanner.deepsec_full_scan(skip_revalidate: true)

      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end

    test "accepts session_id and task_id options" do
      result = Scanner.deepsec_full_scan(session_id: 123, task_id: 456)

      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
        _ -> flunk("Unexpected result: #{inspect(result)}")
      end
    end
  end
end
