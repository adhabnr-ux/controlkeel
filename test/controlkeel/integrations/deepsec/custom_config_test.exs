defmodule ControlKeel.Integrations.Deepsec.CustomConfigTest do
  use ExUnit.Case

  alias ControlKeel.Integrations.Deepsec.CustomConfig

  describe "get_default_config/0" do
    test "returns default configuration" do
      config = CustomConfig.get_default_config()

      assert is_map(config)
      assert Map.has_key?(config, "matchers")
      assert Map.has_key?(config, "filePatterns")
      assert Map.has_key?(config, "severityThreshold")
    end
  end

  describe "validate_config/1" do
    test "validates valid configuration" do
      config = %{
        "matchers" => [
          %{
            "slug" => "test",
            "pattern" => "test",
            "severity" => "high"
          }
        ],
        "filePatterns" => ["**/*.ex"],
        "severityThreshold" => "medium"
      }

      assert {:ok, _} = CustomConfig.validate_config(config)
    end

    test "rejects invalid matchers" do
      config = %{
        "matchers" => [
          %{
            "slug" => "test"
            # Missing required fields
          }
        ]
      }

      assert {:error, _} = CustomConfig.validate_config(config)
    end

    test "rejects invalid file patterns" do
      config = %{
        "filePatterns" => "not a list"
      }

      assert {:error, _} = CustomConfig.validate_config(config)
    end

    test "rejects invalid severity threshold" do
      config = %{
        "severityThreshold" => "invalid"
      }

      assert {:error, _} = CustomConfig.validate_config(config)
    end
  end

  describe "merge_configs/2" do
    test "merges custom config with default" do
      default = %{"key1" => "value1", "key2" => "value2"}
      custom = %{"key2" => "custom_value", "key3" => "value3"}

      merged = CustomConfig.merge_configs(custom, default)

      assert merged["key1"] == "value1"
      assert merged["key2"] == "custom_value"
      assert merged["key3"] == "value3"
    end
  end

  describe "create_starter_config/1" do
    test "creates a starter configuration file" do
      tmp_path = Path.join(System.tmp_dir!(), "starter_config_#{System.unique_integer()}.json")

      {:ok, path} = CustomConfig.create_starter_config(tmp_path)

      assert File.exists?(path)

      {:ok, content} = File.read(path)
      assert {:ok, _} = Jason.decode(content)

      File.rm!(path)
    end
  end
end
