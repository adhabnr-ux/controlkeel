defmodule ControlKeelWeb.CloudTelemetryLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-telemetry-live-test-#{System.unique_integer([:positive])}"
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

    :ok
  end

  describe "mount/render with no telemetry yet" do
    test "shows disabled state and zero counters", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cloud/telemetry")

      assert html =~ "Cloud telemetry"
      assert html =~ "disabled"
      assert html =~ "0 received"
      assert html =~ "0 pending"
      assert html =~ "not connected"
      assert html =~ "unconfigured"
      assert html =~ "No events received yet"
    end
  end

  describe "mount/render with received events" do
    setup do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()
      {:ok, _state} = TelemetryConfig.enable(:governance)

      {:ok, env1} = TelemetryEnvelope.build("install.success", %{"host" => "claude-code"})
      {:ok, env2} = TelemetryEnvelope.build("attach.success", %{"host" => "claude-code"})
      {:ok, env3} = TelemetryEnvelope.build("finding.created", %{"severity" => "high"})

      batch = %{
        "schema_version" => "1",
        "workspace_id" => identity.workspace_id,
        "events" => [env1, env2, env3]
      }

      {:ok, _summary} = Ingestion.ingest(batch, identity.workspace_id)

      {:ok, identity: identity}
    end

    test "shows funnel counts and workspace identity", %{conn: conn, identity: identity} do
      {:ok, _view, html} = live(conn, ~p"/cloud/telemetry")

      assert html =~ "3 received"
      assert html =~ identity.workspace_id
      # All three funnel stages should appear
      assert html =~ "install.success"
      assert html =~ "attach.success"
      assert html =~ "finding.created"
    end

    test "lists recent events with kind and workspace", %{conn: conn, identity: identity} do
      {:ok, _view, html} = live(conn, ~p"/cloud/telemetry")

      assert html =~ "Recent received events"
      assert html =~ identity.workspace_id
      assert html =~ "install.success"
    end

    test "shows governance level pill in the badge stack", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cloud/telemetry")
      assert html =~ "governance"
    end
  end
end
