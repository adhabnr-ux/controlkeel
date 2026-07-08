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
end
