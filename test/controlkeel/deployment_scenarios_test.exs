defmodule ControlKeel.DeploymentScenariosTest do
  @moduledoc """
  Integration tests for CK deployment scenarios.

  Validates that CK works across:
  - Local agents + local CK (default mode)
  - Local agents + cloud CK
  - Local agents + self-hosted CK
  - SDK integration
  - MCP integration
  """

  use ExUnit.Case, async: false

  alias ControlKeel.{Runtime, RuntimeMode}

  setup do
    # Save original environment
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    original_sync_endpoint = Application.get_env(:controlkeel, :cloud_sync_endpoint)

    original_env = %{
      "CONTROLKEEL_RUNTIME_MODE" => System.get_env("CONTROLKEEL_RUNTIME_MODE"),
      "CONTROLKEEL_CLOUD_SYNC_ENDPOINT" => System.get_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT"),
      "PHX_HOST" => System.get_env("PHX_HOST")
    }

    # Clear env vars for clean slate
    System.delete_env("CONTROLKEEL_RUNTIME_MODE")
    System.delete_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT")
    System.delete_env("PHX_HOST")
    Application.delete_env(:controlkeel, :runtime_mode)
    Application.delete_env(:controlkeel, :cloud_sync_endpoint)

    on_exit(fn ->
      # Restore original environment
      Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, original_sync_endpoint)

      Enum.each(original_env, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    :ok
  end

  describe "Scenario 1: Local Agent + Local CK (Default Mode)" do
    test "local mode is default when no configuration is provided" do
      assert RuntimeMode.current() == :local
      assert Runtime.local?()
      refute Runtime.cloud?()
      refute Runtime.self_hosted?()
    end

    test "local mode keeps all surfaces local" do
      placements = RuntimeMode.placement_map(:local)

      assert placements.db == :local
      assert placements.mcp == :local
      assert placements.skills == :local
      assert placements.hooks == :local
      assert placements.cli == :local
      assert placements.web == :local
      assert placements.memory == :local
      assert placements.policy == :local
      assert placements.telemetry == :local
      assert placements.observability == :local
      assert placements.sdk == :local
    end

    test "local mode has no missing requirements" do
      assert RuntimeMode.ready?(:local)
      assert RuntimeMode.missing_requirements(:local) == []
    end

    test "local mode allows any endpoint for development" do
      assert {:ok, "http://localhost:4000"} =
               RuntimeMode.normalize_sync_endpoint("http://localhost:4000/", :local)

      assert {:ok, "https://staging.example.com"} =
               RuntimeMode.normalize_sync_endpoint("https://staging.example.com/", :local)
    end
  end

  describe "Scenario 2: Local Agent + Cloud CK" do
    test "cloud mode requires controlkeel.com endpoint" do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      assert RuntimeMode.current() == :cloud
      assert Runtime.cloud?()
      assert Runtime.remote?()

      # Valid endpoint
      assert {:ok, "https://controlkeel.com"} =
               RuntimeMode.normalize_sync_endpoint("https://controlkeel.com/", :cloud)

      # Invalid endpoint (not controlkeel.com)
      assert {:error, :cloud_endpoint_must_be_controlkeel_com} =
               RuntimeMode.normalize_sync_endpoint("https://self.example.com", :cloud)
    end

    test "cloud mode makes CLI a thin client" do
      placements = RuntimeMode.placement_map(:cloud)

      assert placements.cli == :thin_client
      assert placements.mcp == :cloud
      assert placements.skills == :cloud
      assert placements.web == :cloud
    end

    test "cloud mode reports missing requirements" do
      diagnostic = RuntimeMode.diagnostic(:cloud)

      refute diagnostic.ready?
      assert :cloud_sync_endpoint in diagnostic.missing_requirements
      assert :workspace_identity in diagnostic.missing_requirements
    end

    test "cloud mode becomes ready with proper configuration" do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://controlkeel.com")

      # Note: workspace_identity requires actual workspace setup, so we check other requirements
      missing = RuntimeMode.missing_requirements(:cloud)

      # cloud_sync_endpoint should now be satisfied
      refute :cloud_sync_endpoint in missing
      # workspace_identity still missing (expected in test environment)
      assert :workspace_identity in missing
    end
  end

  describe "Scenario 3: Local Agent + Self-Hosted CK" do
    test "self_hosted mode requires custom endpoint" do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)

      assert RuntimeMode.current() == :self_hosted
      assert Runtime.self_hosted?()
      assert Runtime.remote?()

      # Valid custom endpoint
      assert {:ok, "https://ck.example.com"} =
               RuntimeMode.normalize_sync_endpoint("https://ck.example.com/", :self_hosted)

      # Invalid endpoint (controlkeel.com is reserved for cloud mode)
      assert {:error, :self_hosted_endpoint_must_not_be_controlkeel_com} =
               RuntimeMode.normalize_sync_endpoint("https://controlkeel.com", :self_hosted)
    end

    test "self_hosted mode makes CLI a thin client" do
      placements = RuntimeMode.placement_map(:self_hosted)

      assert placements.cli == :thin_client
      assert placements.mcp == :self_hosted
      assert placements.skills == :self_hosted
      assert placements.web == :self_hosted
    end

    test "self_hosted mode requires PHX_HOST and endpoint" do
      diagnostic = RuntimeMode.diagnostic(:self_hosted)

      refute diagnostic.ready?
      assert :cloud_sync_endpoint in diagnostic.missing_requirements
      assert :phx_host in diagnostic.missing_requirements
      assert :workspace_identity in diagnostic.missing_requirements
    end

    test "self_hosted mode becomes ready with proper configuration" do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      Application.put_env(:controlkeel, :cloud_sync_endpoint, "https://ck.example.com")
      System.put_env("PHX_HOST", "ck.example.com")

      missing = RuntimeMode.missing_requirements(:self_hosted)

      # cloud_sync_endpoint and phx_host should now be satisfied
      refute :cloud_sync_endpoint in missing
      refute :phx_host in missing
      # workspace_identity still missing (expected in test environment)
      assert :workspace_identity in missing
    end
  end

  describe "Cross-Scenario: Mode Switching" do
    test "can switch from local to cloud mode" do
      # Start in local mode
      Application.put_env(:controlkeel, :runtime_mode, :local)
      assert RuntimeMode.current() == :local
      assert RuntimeMode.placement_map(:local).cli == :local

      # Switch to cloud mode
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      assert RuntimeMode.current() == :cloud
      assert RuntimeMode.placement_map(:cloud).cli == :thin_client
    end

    test "can switch from local to self_hosted mode" do
      # Start in local mode
      Application.put_env(:controlkeel, :runtime_mode, :local)
      assert RuntimeMode.current() == :local

      # Switch to self_hosted mode
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      assert RuntimeMode.current() == :self_hosted
      assert RuntimeMode.placement_map(:self_hosted).cli == :thin_client
    end

    test "environment variable overrides config" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      System.put_env("CONTROLKEEL_RUNTIME_MODE", "cloud")

      assert RuntimeMode.current() == :cloud
    end
  end

  describe "Surface Placement Validation" do
    test "all 11 surfaces have defined placements in each mode" do
      surfaces = RuntimeMode.surfaces()

      local_placements = RuntimeMode.placement_map(:local)
      cloud_placements = RuntimeMode.placement_map(:cloud)
      self_hosted_placements = RuntimeMode.placement_map(:self_hosted)

      # All surfaces have placements in each mode
      assert Map.keys(local_placements) |> Enum.sort() == surfaces |> Enum.sort()
      assert Map.keys(cloud_placements) |> Enum.sort() == surfaces |> Enum.sort()
      assert Map.keys(self_hosted_placements) |> Enum.sort() == surfaces |> Enum.sort()
    end

    test "placement contracts are consistent across modes" do
      # CLI is thin client in cloud/self_hosted, local in local mode
      assert RuntimeMode.placement(:local, :cli) == :local
      assert RuntimeMode.placement(:cloud, :cli) == :thin_client
      assert RuntimeMode.placement(:self_hosted, :cli) == :thin_client

      # All other surfaces follow the mode pattern
      for surface <- [
            :db,
            :mcp,
            :skills,
            :hooks,
            :web,
            :memory,
            :policy,
            :telemetry,
            :observability,
            :sdk
          ] do
        assert RuntimeMode.placement(:local, surface) == :local
        assert RuntimeMode.placement(:cloud, surface) == :cloud
        assert RuntimeMode.placement(:self_hosted, surface) == :self_hosted
      end
    end
  end
end
