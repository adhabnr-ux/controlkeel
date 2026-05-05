defmodule ControlKeel.Integrations.Deepsec.ConfigTest do
  use ControlKeel.DataCase

  alias ControlKeel.Integrations.Deepsec.Config

  describe "enabled?/0" do
    test "returns false by default" do
      assert Config.enabled?() == false
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, enabled: true)

      assert Config.enabled?() == true

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "use_for_security_domain?/0" do
    test "returns false by default" do
      assert Config.use_for_security_domain?() == false
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, use_for_security_domain: true)

      assert Config.use_for_security_domain?() == true

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "min_severity_for_investigation/0" do
    test "returns :high by default" do
      assert Config.min_severity_for_investigation() == :high
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, min_severity_for_investigation: :critical)

      assert Config.min_severity_for_investigation() == :critical

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "block_on_security_findings?/0" do
    test "returns false by default" do
      assert Config.block_on_security_findings?() == false
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, block_on_security_findings: true)

      assert Config.block_on_security_findings?() == true

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "max_scan_budget_cents/0" do
    test "returns 10000 by default" do
      assert Config.max_scan_budget_cents() == 10_000
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, max_scan_budget_cents: 5000)

      assert Config.max_scan_budget_cents() == 5000

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "workspace_path/0" do
    test "returns '.deepsec' by default" do
      assert Config.workspace_path() == ".deepsec"
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, workspace_path: "/custom/path")

      assert Config.workspace_path() == "/custom/path"

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "auto_create_proof_bundles?/0" do
    test "returns true by default" do
      assert Config.auto_create_proof_bundles?() == true
    end

    test "returns configured value" do
      Application.put_env(:controlkeel, :deepsec, auto_create_proof_bundles: false)

      assert Config.auto_create_proof_bundles?() == false

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "custom_matchers/0" do
    test "returns empty list by default" do
      assert Config.custom_matchers() == []
    end

    test "returns configured value" do
      matchers = [%{name: "custom", pattern: "test"}]
      Application.put_env(:controlkeel, :deepsec, custom_matchers: matchers)

      assert Config.custom_matchers() == matchers

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "validate_config/0" do
    test "returns :ok for valid default config" do
      assert Config.validate_config() == :ok
    end

    test "returns error for negative budget" do
      Application.put_env(:controlkeel, :deepsec, max_scan_budget_cents: -100)

      assert {:error, errors} = Config.validate_config()
      assert "max_scan_budget_cents must be non-negative" in errors

      Application.delete_env(:controlkeel, :deepsec)
    end

    test "returns error for invalid severity" do
      Application.put_env(:controlkeel, :deepsec, min_severity_for_investigation: :invalid)

      assert {:error, errors} = Config.validate_config()
      assert "min_severity_for_investigation must be :low, :medium, :high, or :critical" in errors

      Application.delete_env(:controlkeel, :deepsec)
    end
  end

  describe "inspect_config/0" do
    test "returns configuration map" do
      config = Config.inspect_config()

      assert is_map(config)
      assert Map.has_key?(config, :deepsec_enabled)
      assert Map.has_key?(config, :use_for_security_domain)
      assert Map.has_key?(config, :min_severity_for_investigation)
      assert Map.has_key?(config, :block_on_security_findings)
      assert Map.has_key?(config, :max_scan_budget_cents)
      assert Map.has_key?(config, :workspace_path)
      assert Map.has_key?(config, :auto_create_proof_bundles)
      assert Map.has_key?(config, :custom_matchers_count)
      assert Map.has_key?(config, :matcher_system_enabled)
      assert Map.has_key?(config, :ai_investigation_enabled)
    end
  end
end
