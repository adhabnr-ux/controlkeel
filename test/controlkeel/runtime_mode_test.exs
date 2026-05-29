defmodule ControlKeel.RuntimeModeTest do
  use ExUnit.Case, async: false

  alias ControlKeel.{Runtime, RuntimeDefaults, RuntimeMode, SelfHost}

  setup do
    previous_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
    previous_sync_endpoint = Application.get_env(:controlkeel, :cloud_sync_endpoint)
    previous_cloud_repo = Application.get_env(:controlkeel, ControlKeel.CloudRepo)

    previous_env = %{
      "CONTROLKEEL_RUNTIME_MODE" => System.get_env("CONTROLKEEL_RUNTIME_MODE"),
      "CONTROLKEEL_CLOUD_SYNC_ENDPOINT" => System.get_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT"),
      "CONTROLKEEL_HOME" => System.get_env("CONTROLKEEL_HOME"),
      "PHX_HOST" => System.get_env("PHX_HOST"),
      "PHX_URL_SCHEME" => System.get_env("PHX_URL_SCHEME"),
      "PHX_URL_PORT" => System.get_env("PHX_URL_PORT")
    }

    tmp_home =
      Path.join(System.tmp_dir!(), "ck-runtime-mode-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_home)
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      restore_app_env(:runtime_mode, previous_runtime_mode)
      restore_app_env(:cloud_sync_endpoint, previous_sync_endpoint)
      restore_app_env(ControlKeel.CloudRepo, previous_cloud_repo)

      Enum.each(previous_env, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      File.rm_rf!(tmp_home)
    end)

    Application.delete_env(:controlkeel, :runtime_mode)
    Application.delete_env(:controlkeel, :cloud_sync_endpoint)
    Application.delete_env(:controlkeel, ControlKeel.CloudRepo)
    System.delete_env("CONTROLKEEL_RUNTIME_MODE")
    System.delete_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT")
    System.delete_env("PHX_HOST")
    System.delete_env("PHX_URL_SCHEME")
    System.delete_env("PHX_URL_PORT")

    :ok
  end

  describe "parse/1 and current/0" do
    test "supports local, cloud, and self-hosted aliases" do
      assert RuntimeMode.parse(nil) == :local
      assert RuntimeMode.parse("local") == :local
      assert RuntimeMode.parse("cloud") == :cloud
      assert RuntimeMode.parse("self_hosted") == :self_hosted
      assert RuntimeMode.parse("self-hosted") == :self_hosted
      assert RuntimeMode.parse("selfhost") == :self_hosted
      assert RuntimeMode.parse("unexpected") == :local
    end

    test "env overrides application config for runtime process defaults" do
      System.put_env("CONTROLKEEL_RUNTIME_MODE", "cloud")
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)

      assert RuntimeMode.current() == :cloud
      assert Runtime.mode() == :cloud
      assert Runtime.cloud?()
      assert Runtime.remote?()
    end

    test "application config is used when env is absent" do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)

      assert RuntimeMode.current() == :self_hosted
      assert Runtime.self_hosted?()
      assert Runtime.remote?()
    end
  end

  describe "placement contract" do
    test "local mode keeps every governed surface local" do
      placements = RuntimeMode.placement_map(:local)

      assert Map.keys(placements) |> Enum.sort() == RuntimeMode.surfaces() |> Enum.sort()
      assert Enum.all?(placements, fn {_surface, placement} -> placement == :local end)
    end

    test "cloud and self-hosted modes make CLI a thin client and move workloads remote" do
      cloud = RuntimeMode.placement_map(:cloud)
      self_hosted = RuntimeMode.placement_map(:self_hosted)

      assert cloud.cli == :thin_client
      assert cloud.mcp == :cloud
      assert cloud.skills == :cloud
      assert cloud.hooks == :cloud
      assert cloud.memory == :cloud
      assert cloud.policy == :cloud
      assert cloud.telemetry == :cloud
      assert cloud.observability == :cloud
      assert cloud.sdk == :cloud

      assert self_hosted.cli == :thin_client
      assert self_hosted.mcp == :self_hosted
      assert self_hosted.skills == :self_hosted
      assert self_hosted.hooks == :self_hosted
      assert self_hosted.memory == :self_hosted
      assert self_hosted.policy == :self_hosted
      assert self_hosted.telemetry == :self_hosted
      assert self_hosted.observability == :self_hosted
      assert self_hosted.sdk == :self_hosted
    end
  end

  describe "fail-closed diagnostics" do
    test "cloud mode reports missing endpoint and identity" do
      diagnostic = RuntimeMode.diagnostic(:cloud)

      refute diagnostic.ready?
      assert :cloud_sync_endpoint in diagnostic.missing_requirements
      assert :workspace_identity in diagnostic.missing_requirements
    end

    test "self-hosted mode also requires an explicit host and never defaults to SaaS" do
      diagnostic = RuntimeMode.diagnostic(:self_hosted)

      refute diagnostic.ready?
      assert :cloud_sync_endpoint in diagnostic.missing_requirements
      assert :phx_host in diagnostic.missing_requirements
      assert :workspace_identity in diagnostic.missing_requirements

      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      endpoint = RuntimeDefaults.endpoint_url_config()

      assert endpoint[:host] == "localhost"
      refute endpoint[:host] == "controlkeel.com"
      assert endpoint[:scheme] == "https"
    end

    test "cloud mode keeps canonical SaaS endpoint default" do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      endpoint = RuntimeDefaults.endpoint_url_config()

      assert endpoint[:host] == "controlkeel.com"
      assert endpoint[:scheme] == "https"
      assert endpoint[:port] == 443
    end
  end

  describe "sync endpoint contract" do
    test "cloud mode only accepts the canonical SaaS host" do
      assert {:ok, "https://controlkeel.com"} =
               RuntimeMode.normalize_sync_endpoint("https://controlkeel.com/", :cloud)

      assert {:error, :cloud_endpoint_must_be_controlkeel_com} =
               RuntimeMode.normalize_sync_endpoint("https://self.example.com", :cloud)
    end

    test "self-hosted mode rejects the canonical SaaS host" do
      assert {:ok, "https://ck.example.com"} =
               RuntimeMode.normalize_sync_endpoint("https://ck.example.com/", :self_hosted)

      assert {:error, :self_hosted_endpoint_must_not_be_controlkeel_com} =
               RuntimeMode.normalize_sync_endpoint("https://controlkeel.com", :self_hosted)
    end

    test "local mode can use an explicitly configured endpoint for development" do
      assert {:ok, "http://localhost:4000"} =
               RuntimeMode.normalize_sync_endpoint("http://localhost:4000/", :local)
    end
  end

  describe "self-host readiness" do
    test "self-hosted mode is first-class and requires remote repo configuration" do
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)

      result = SelfHost.verify_environment()

      assert result.repo.mode == :self_hosted
      assert result.repo.cloud_repo_enabled? == false
      assert result.repo.repo_reachable? == false
      assert result.repo.error == "self-hosted mode requires CloudRepo configuration"
      refute result.ready?
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:controlkeel, key)
  defp restore_app_env(key, value), do: Application.put_env(:controlkeel, key, value)
end
