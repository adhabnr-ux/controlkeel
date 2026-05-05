defmodule ControlKeel.Validation.Matchers.MatcherTest do
  use ExUnit.Case

  alias ControlKeel.Validation.Matchers.Matcher

  describe "new/5" do
    test "creates a new matcher with valid parameters" do
      matcher =
        Matcher.new(
          "test-slug",
          :precise,
          ["**/*.ex"],
          [~r/test/],
          "Test matcher"
        )

      assert matcher.slug == "test-slug"
      assert matcher.noise_tier == :precise
      assert matcher.file_patterns == ["**/*.ex"]
      assert is_list(matcher.regex_patterns)
      assert matcher.description == "Test matcher"
      assert matcher.category == "security"
      assert matcher.severity == "medium"
    end

    test "accepts custom options" do
      matcher =
        Matcher.new(
          "test-slug",
          :normal,
          ["**/*.js"],
          [~r/test/],
          "Test matcher",
          category: "quality",
          severity: "high",
          metadata: %{custom: true}
        )

      assert matcher.category == "quality"
      assert matcher.severity == "high"
      assert matcher.metadata == %{custom: true}
    end

    test "raises on invalid noise tier" do
      assert_raise RuntimeError, ~r/Invalid noise tier/, fn ->
        Matcher.new("test", :invalid, ["**/*.ex"], [~r/test/], "Test")
      end
    end

    test "compiles string regex patterns" do
      matcher = Matcher.new("test", :precise, ["**/*.ex"], ["test"], "Test")

      assert is_list(matcher.regex_patterns)
      assert is_struct(hd(matcher.regex_patterns), Regex)
    end
  end

  describe "matches?/3" do
    test "returns matches when file pattern and content match" do
      matcher = Matcher.new("test", :precise, [".ex"], [~r/query_raw/], "Test")

      assert {:ok, _matches} = Matcher.matches?(matcher, "app/models/user.ex", "Repo.query_raw()")
    end

    test "returns error when file pattern doesn't match" do
      matcher = Matcher.new("test", :precise, [".ex"], [~r/test/], "Test")

      assert :error == Matcher.matches?(matcher, "app/models/user.js", "test content")
    end

    test "returns error when content doesn't match" do
      matcher = Matcher.new("test", :precise, [".ex"], [~r/query_raw/], "Test")

      assert :error == Matcher.matches?(matcher, "app/models/user.ex", "safe code")
    end

    test "handles multiple regex patterns" do
      matcher =
        Matcher.new("test", :normal, [".ex"], [~r/pattern1/, ~r/pattern2/], "Test")

      assert {:ok, _matches} = Matcher.matches?(matcher, "test.ex", "pattern1 here")
      assert {:ok, _matches} = Matcher.matches?(matcher, "test.ex", "pattern2 here")
    end
  end

  describe "tier_priority/1" do
    test "returns priority for noise tiers" do
      assert Matcher.tier_priority(:precise) == 0
      assert Matcher.tier_priority(:normal) == 1
      assert Matcher.tier_priority(:noisy) == 2
    end
  end
end
