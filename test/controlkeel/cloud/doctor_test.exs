defmodule ControlKeel.Cloud.DoctorTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.Doctor

  setup do
    original_mode = Application.get_env(:controlkeel, :runtime_mode)
    original_repo_config = Application.get_env(:controlkeel, ControlKeel.CloudRepo)
    original_database_url = System.get_env("DATABASE_URL")
    original_nats_url = System.get_env("CONTROLKEEL_NATS_URL")
    original_runtime_env = System.get_env("CONTROLKEEL_RUNTIME_MODE")
    original_phx_host = System.get_env("PHX_HOST")
    original_endpoint = Application.get_env(:controlkeel, ControlKeelWeb.Endpoint)

    on_exit(fn ->
      if original_endpoint do
        Application.put_env(:controlkeel, ControlKeelWeb.Endpoint, original_endpoint)
      else
        Application.delete_env(:controlkeel, ControlKeelWeb.Endpoint)
      end

      restore_env("PHX_HOST", original_phx_host)
    end)

    on_exit(fn ->
      if original_mode do
        Application.put_env(:controlkeel, :runtime_mode, original_mode)
      else
        Application.delete_env(:controlkeel, :runtime_mode)
      end

      if original_repo_config do
        Application.put_env(:controlkeel, ControlKeel.CloudRepo, original_repo_config)
      else
        Application.delete_env(:controlkeel, ControlKeel.CloudRepo)
      end

      restore_env("DATABASE_URL", original_database_url)
      restore_env("CONTROLKEEL_NATS_URL", original_nats_url)
      restore_env("CONTROLKEEL_RUNTIME_MODE", original_runtime_env)
    end)

    :ok
  end

  describe "report/0 in local mode" do
    setup do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      :ok
    end

    test "returns ok: true and marks cloud-only checks not_applicable" do
      report = Doctor.report()

      assert report.mode == :local
      assert report.ok == true

      check = find_check(report, :cloud_repo)
      assert check.status == :not_applicable
      assert check.detail =~ "local mode"

      sa = find_check(report, :service_accounts)
      assert sa.status == :not_applicable
    end

    test "telemetry sync is reported as disabled" do
      report = Doctor.report()
      telemetry = find_check(report, :telemetry_sync)

      assert telemetry.status == :info
      assert telemetry.detail =~ "disabled"
    end

    test "format/1 renders human-readable lines" do
      report = Doctor.report()
      lines = Doctor.format(report)

      assert Enum.any?(lines, &(&1 == "ControlKeel cloud doctor"))
      assert Enum.any?(lines, &String.starts_with?(&1, "Mode: "))
      assert Enum.any?(lines, &String.starts_with?(&1, "Overall: "))
    end
  end

  describe "report/0 in cloud mode" do
    setup do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      :ok
    end

    test "flags missing CloudRepo config as error" do
      Application.delete_env(:controlkeel, ControlKeel.CloudRepo)

      report = Doctor.report()

      assert report.mode == :cloud
      cloud_repo = find_check(report, :cloud_repo)
      assert cloud_repo.status == :error
      assert cloud_repo.detail =~ "config is empty"
      assert report.ok == false
    end

    test "flags missing DATABASE_URL when CloudRepo is configured" do
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgres://placeholder")
      System.delete_env("DATABASE_URL")

      report = Doctor.report()

      cloud_repo = find_check(report, :cloud_repo)
      assert cloud_repo.status == :error
      assert cloud_repo.detail =~ "DATABASE_URL"
      assert report.ok == false
    end

    test "reports ok when CloudRepo config and DATABASE_URL are present" do
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgres://placeholder")
      System.put_env("DATABASE_URL", "postgres://example/db")

      report = Doctor.report()

      cloud_repo = find_check(report, :cloud_repo)
      assert cloud_repo.status == :ok
    end

    test "service-account check returns ok when none are configured" do
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgres://placeholder")
      System.put_env("DATABASE_URL", "postgres://example/db")

      report = Doctor.report()
      sa = find_check(report, :service_accounts)

      assert sa.status in [:ok, :info]
      assert sa.detail =~ "none configured" or sa.detail =~ "configured"
    end
  end

  describe "report/0 bus checks" do
    test "Bus.Local reports info status in any mode" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      Application.put_env(:controlkeel, :bus, :local)

      report = Doctor.report()
      bus = find_check(report, :bus)

      assert bus.status == :info
      assert bus.detail =~ "Bus.Local"
    end
  end

  describe "report/0 hosted MCP / A2A routes" do
    setup do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      :ok
    end

    test "hosted MCP route is registered" do
      report = Doctor.report()
      mcp = find_check(report, :hosted_mcp)

      assert mcp.status == :ok
      assert mcp.detail =~ "/mcp"
    end

    test "A2A route and agent-card are registered" do
      report = Doctor.report()
      a2a = find_check(report, :a2a)

      assert a2a.status == :ok
      assert a2a.detail =~ "/a2a"
    end
  end

  describe "public_host check" do
    setup do
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgres://placeholder")
      System.put_env("DATABASE_URL", "postgres://example/db")
      :ok
    end

    test "is :not_applicable in local mode" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      System.delete_env("PHX_HOST")

      report = Doctor.report()
      host = find_check(report, :public_host)
      assert host.status == :not_applicable
    end

    test "warns when PHX_HOST is unset in cloud mode" do
      System.delete_env("PHX_HOST")

      Application.put_env(:controlkeel, ControlKeelWeb.Endpoint, url: [host: nil])

      report = Doctor.report()
      host = find_check(report, :public_host)
      assert host.status == :warn
      assert host.detail =~ "PHX_HOST"
    end

    test "reports canonical SaaS when host is controlkeel.com" do
      System.put_env("PHX_HOST", "controlkeel.com")

      report = Doctor.report()
      host = find_check(report, :public_host)
      assert host.status == :ok
      assert host.detail =~ "canonical SaaS"
    end

    test "reports self-host when PHX_HOST is anything else" do
      System.put_env("PHX_HOST", "govern.acme.example")

      report = Doctor.report()
      host = find_check(report, :public_host)
      assert host.status == :ok
      assert host.detail =~ "self-host"
      assert host.detail =~ "govern.acme.example"
    end
  end

  defp find_check(report, id) do
    Enum.find(report.checks, &(&1.id == id)) ||
      flunk("missing check #{inspect(id)} in #{inspect(report.checks)}")
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
