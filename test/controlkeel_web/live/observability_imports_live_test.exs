defmodule ControlKeelWeb.ObservabilityImportsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry

  test "imports page renders persisted observability snapshots", %{conn: conn} do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-imports-live-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, result} =
             ObservabilityTelemetry.import_persist(path,
               workspace_id: session.workspace_id,
               session_id: session.id,
               imported_at: ~U[2026-04-29 05:00:00Z]
             )

    {:ok, view, html} = live(conn, ~p"/observability/imports")

    assert html =~ "Imported snapshots"
    assert has_element?(view, "#observability-imports-page")
    assert has_element?(view, "#observability-imports-count")
    assert has_element?(view, "#observability-imports-integrity")
    assert has_element?(view, "#observability-imports-health")
    assert has_element?(view, "#observability-imports-recommendations")
    assert has_element?(view, "#observability-imports-list")
    assert has_element?(view, "#observability-import-#{result.id}")
    assert html =~ "verified"
    assert html =~ "mutation none"
    assert html =~ session.title
  end
end
