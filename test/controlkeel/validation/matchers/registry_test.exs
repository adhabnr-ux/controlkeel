defmodule ControlKeel.Validation.Matchers.RegistryTest do
  use ExUnit.Case

  alias ControlKeel.Validation.Matchers.{Matcher, Registry}

  setup do
    # Start the registry for each test
    start_supervised!(Registry)
    Registry.clear()
    :ok
  end

  describe "register/1" do
    test "registers a new matcher" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")

      assert :ok == Registry.register(matcher)
      assert {:ok, ^matcher} = Registry.get("test-slug")
    end

    test "raises when slug already exists" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert_raise RuntimeError, ~r/already registered/, fn ->
        Registry.register(matcher)
      end
    end
  end

  describe "register!/1" do
    test "registers and replaces existing matcher" do
      matcher1 = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")

      matcher2 =
        Matcher.new("test-slug", :normal, ["**/*.js"], [~r/pattern/], "Updated")

      assert :ok == Registry.register(matcher1)
      assert :ok == Registry.register!(matcher2)

      assert {:ok, updated} = Registry.get("test-slug")
      assert updated.noise_tier == :normal
    end
  end

  describe "get/1" do
    test "returns matcher by slug" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert {:ok, ^matcher} = Registry.get("test-slug")
    end

    test "returns error for non-existent slug" do
      assert :error == Registry.get("non-existent")
    end
  end

  describe "get!/1" do
    test "returns matcher by slug" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert ^matcher = Registry.get!("test-slug")
    end

    test "raises for non-existent slug" do
      assert_raise RuntimeError, ~r/not found/, fn ->
        Registry.get!("non-existent")
      end
    end
  end

  describe "all/0" do
    test "returns all registered matchers" do
      matcher1 = Matcher.new("slug1", :precise, ["**/*.ex"], [~r/test/], "Test 1")
      matcher2 = Matcher.new("slug2", :normal, ["**/*.js"], [~r/pattern/], "Test 2")

      Registry.register(matcher1)
      Registry.register(matcher2)

      matchers = Registry.all()
      assert length(matchers) == 2
    end

    test "returns empty list when no matchers registered" do
      assert Registry.all() == []
    end
  end

  describe "all_sorted/0" do
    test "returns matchers sorted by noise tier" do
      matcher1 = Matcher.new("slug1", :noisy, ["**/*.ex"], [~r/test/], "Test 1")
      matcher2 = Matcher.new("slug2", :precise, ["**/*.js"], [~r/pattern/], "Test 2")
      matcher3 = Matcher.new("slug3", :normal, ["**/*.py"], [~r/regex/], "Test 3")

      Registry.register(matcher1)
      Registry.register(matcher2)
      Registry.register(matcher3)

      matchers = Registry.all_sorted()
      assert length(matchers) == 3
      assert hd(matchers).noise_tier == :precise
      assert List.last(matchers).noise_tier == :noisy
    end
  end

  describe "for_file/1" do
    test "returns matchers that match the file path" do
      matcher1 = Matcher.new("slug1", :precise, ["**/*.ex"], [~r/test/], "Test 1")
      matcher2 = Matcher.new("slug2", :normal, ["**/*.js"], [~r/pattern/], "Test 2")

      Registry.register(matcher1)
      Registry.register(matcher2)

      matchers = Registry.for_file("app/models/user.ex")
      assert length(matchers) == 1
      assert hd(matchers).slug == "slug1"
    end

    test "returns empty list when no matchers match the file" do
      matcher = Matcher.new("slug1", :precise, ["**/*.ex"], [~r/test/], "Test 1")
      Registry.register(matcher)

      matchers = Registry.for_file("app/models/user.js")
      assert matchers == []
    end
  end

  describe "clear/0" do
    test "removes all registered matchers" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert :ok == Registry.clear()
      assert Registry.all() == []
    end
  end

  describe "remove/1" do
    test "removes matcher by slug" do
      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert :ok == Registry.remove("test-slug")
      assert :error == Registry.get("test-slug")
    end

    test "does nothing when slug doesn't exist" do
      assert :ok == Registry.remove("non-existent")
    end
  end

  describe "count/0" do
    test "returns number of registered matchers" do
      assert Registry.count() == 0

      matcher = Matcher.new("test-slug", :precise, ["**/*.ex"], [~r/test/], "Test")
      Registry.register(matcher)

      assert Registry.count() == 1
    end
  end

  describe "load_built_ins/0" do
    test "loads built-in security matchers" do
      assert :ok == Registry.load_built_ins()
      assert Registry.count() > 0
    end

    test "clears existing matchers before loading built-ins" do
      custom = Matcher.new("custom", :precise, ["**/*.ex"], [~r/test/], "Custom")
      Registry.register(custom)

      assert :ok == Registry.load_built_ins()
      assert :error == Registry.get("custom")
      assert Registry.count() > 0
    end
  end
end
