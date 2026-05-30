defmodule ControlKeel.Cloud.TelemetryConfigTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.TelemetryConfig

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-telemetry-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, tmp_home: tmp_home}
  end

  describe "load/0 default state" do
    test "returns :disabled when the config file does not exist", %{tmp_home: tmp_home} do
      state = TelemetryConfig.load()

      assert state.level == :disabled
      assert state.source == :default
      assert state.load_error == nil
      assert state.workspace_id == nil
      assert state.enabled_at == nil
      assert String.contains?(state.path, tmp_home)
      assert state.path |> Path.basename() == "cloud-telemetry.json"
    end

    test "default state is reported as not enabled" do
      refute TelemetryConfig.enabled?(TelemetryConfig.load())
    end

    test "default summary is human-readable" do
      assert TelemetryConfig.summary(TelemetryConfig.load()) =~ "disabled"
    end
  end

  describe "load/0 with an existing valid config" do
    test "parses a fully-populated config file" do
      write_config(%{
        "level" => "governance",
        "enabled_at" => "2026-05-23T20:00:00Z",
        "workspace_id" => "ws_abc",
        "redaction_policy_version" => "2026.05",
        "schema_version" => "1"
      })

      state = TelemetryConfig.load()

      assert state.level == :governance
      assert state.source == :file
      assert state.workspace_id == "ws_abc"
      assert %DateTime{} = state.enabled_at
      assert state.redaction_policy_version == "2026.05"
      assert state.schema_version == "1"
      assert state.load_error == nil
      assert TelemetryConfig.enabled?(state)
    end

    test "summary includes workspace and timestamp when enabled" do
      write_config(%{
        "level" => "health",
        "enabled_at" => "2026-05-23T20:00:00Z",
        "workspace_id" => "ws_xyz"
      })

      summary = TelemetryConfig.summary(TelemetryConfig.load())

      assert summary =~ "level=health"
      assert summary =~ "workspace=ws_xyz"
      assert summary =~ "enabled_at=2026-05-23"
    end
  end

  describe "load/0 with malformed config" do
    test "falls back to :disabled and records a parse error on invalid JSON" do
      write_config_raw("not json")

      state = TelemetryConfig.load()

      assert state.level == :disabled
      assert is_binary(state.load_error)
      assert state.load_error =~ "JSON parse error"
      refute TelemetryConfig.enabled?(state)
    end

    test "falls back to :disabled when the file is a JSON array" do
      write_config_raw("[1, 2, 3]")

      state = TelemetryConfig.load()

      assert state.level == :disabled
      assert state.load_error =~ "not a JSON object"
    end

    test "falls back to :disabled when the level is unknown" do
      write_config(%{"level" => "evil_mode"})

      state = TelemetryConfig.load()

      assert state.level == :disabled
      assert state.load_error =~ "unknown level"
    end
  end

  describe "levels/0" do
    test "exposes the canonical cumulative ordering" do
      assert TelemetryConfig.levels() == [:disabled, :health, :governance, :evidence, :full_audit]
    end
  end

  defp write_config(map) do
    write_config_raw(Jason.encode!(map))
  end

  defp write_config_raw(body) do
    path = TelemetryConfig.path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  describe "enable/1 and disable/0" do
    alias ControlKeel.Cloud.WorkspaceIdentity

    test "returns :not_connected when no workspace identity exists" do
      assert {:error, :not_connected} = TelemetryConfig.enable(:health)
    end

    test "enables at :health level after cloud connect" do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()

      {:ok, state} = TelemetryConfig.enable(:health)

      assert state.level == :health
      assert state.workspace_id == identity.workspace_id
      assert %DateTime{} = state.enabled_at
      assert state.source == :file
      assert state.load_error == nil
      assert TelemetryConfig.enabled?(state)
    end

    test "enables at every opt-in level" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()

      for level <- TelemetryConfig.opt_in_levels() do
        {:ok, state} = TelemetryConfig.enable(level)
        assert state.level == level
      end
    end

    test "rejects :disabled as a level (use disable/0 instead)" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      assert {:error, :invalid_level} = TelemetryConfig.enable(:disabled)
    end

    test "rejects unknown levels" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      assert {:error, :invalid_level} = TelemetryConfig.enable(:full_paranoid)
    end

    test "disable/0 writes durable disabled state" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _enabled} = TelemetryConfig.enable(:governance)

      {:ok, state} = TelemetryConfig.disable()

      assert state.level == :disabled
      assert state.source == :file
      assert state.workspace_id == nil
      assert state.enabled_at == nil
      refute TelemetryConfig.enabled?(state)
    end

    test "disabled state persists across reloads" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _disabled} = TelemetryConfig.disable()

      reloaded = TelemetryConfig.load()
      assert reloaded.level == :disabled
      assert reloaded.source == :file
    end

    test "config file is written with 0600 permissions" do
      {:ok, _identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _enabled} = TelemetryConfig.enable(:health)

      {:ok, stat} = File.stat(TelemetryConfig.path())
      perm = Bitwise.band(stat.mode, 0o777)
      assert perm == 0o600
    end
  end

  describe "parse_level/1" do
    test "accepts known atoms and strings" do
      assert {:ok, :health} = TelemetryConfig.parse_level(:health)
      assert {:ok, :health} = TelemetryConfig.parse_level("health")
      assert {:ok, :full_audit} = TelemetryConfig.parse_level("full_audit")
    end

    test "rejects unknown values" do
      assert :error = TelemetryConfig.parse_level("evil")
      assert :error = TelemetryConfig.parse_level(:evil)
      assert :error = TelemetryConfig.parse_level(nil)
      assert :error = TelemetryConfig.parse_level(123)
    end
  end
end
