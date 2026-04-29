defmodule ControlKeelWeb.ObservabilityMemoryLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  test "memory page renders summary-only session memory and context", %{conn: conn} do
    session = session_fixture()
    task_fixture(%{session: session})
    finding_fixture(%{session: session})

    memory_record_fixture(%{
      session: session,
      record_type: "decision",
      title: "Memory page decision",
      summary: "Keep memory visible as a summary.",
      source_type: "agent",
      tags: ["observability"]
    })

    {:ok, view, html} = live(conn, ~p"/observability/sessions/#{session.id}/memory")

    assert html =~ "Context and memory"
    assert has_element?(view, "#observability-memory-page")
    assert has_element?(view, "#observability-memory-total")
    assert has_element?(view, "#observability-memory-summary")
    assert has_element?(view, "#observability-memory-recommendations")
    assert has_element?(view, "#observability-memory-records")
    assert html =~ "Memory page decision"
    assert html =~ "Keep memory visible as a summary."
    assert html =~ "/observability/sessions/#{session.id}"
    assert html =~ "/observability/memory-quality"
  end
end
