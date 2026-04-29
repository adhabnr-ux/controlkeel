defmodule ControlKeelWeb.ObservabilityMemoryQualityLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "memory quality page renders workspace memory diagnostics", %{conn: conn} do
    session = session_fixture()

    memory_record_fixture(%{
      session: session,
      record_type: "decision",
      title: "Memory quality page",
      summary: "Summary-only memory diagnostics.",
      source_type: "agent"
    })

    memory_record_fixture(%{
      session: session,
      record_type: "decision",
      title: "Superseded page memory",
      summary: "This is superseded.",
      tags: ["superseded"],
      source_type: "review"
    })

    {:ok, view, html} = live(conn, ~p"/observability/memory-quality")

    assert html =~ "Memory quality"
    assert has_element?(view, "#observability-memory-quality-page")
    assert has_element?(view, "#observability-memory-quality-threshold")
    assert has_element?(view, "#observability-memory-quality-total")
    assert has_element?(view, "#observability-memory-quality-stale")
    assert has_element?(view, "#observability-memory-quality-duplicates")
    assert has_element?(view, "#observability-memory-quality-missed")
    assert has_element?(view, "#observability-memory-quality-distributions")
    assert has_element?(view, "#observability-memory-quality-recommendations")
    assert has_element?(view, "#observability-memory-quality-contradictions")
    assert html =~ "Superseded page memory"
  end
end
