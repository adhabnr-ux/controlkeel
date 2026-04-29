defmodule ControlKeelWeb.ObservabilityBenchmarkDraftsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "benchmark drafts page renders generated drafts", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Benchmark draft page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.benchmark_page"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    {:ok, view, html} = live(conn, ~p"/observability/benchmarks/drafts")

    assert html =~ "Benchmark drafts"
    assert has_element?(view, "#observability-benchmark-drafts-page")
    assert has_element?(view, "#observability-benchmark-drafts-count")
    assert has_element?(view, "#observability-benchmark-drafts-status")
    assert has_element?(view, "#observability-benchmark-drafts-suites")
    assert has_element?(view, "#observability-benchmark-drafts-recommendations")
    assert has_element?(view, "#observability-benchmark-drafts-list")
    assert html =~ "Benchmark draft for security.benchmark_page"
    assert html =~ "Human gate required: true"
    assert html =~ "not materialized"
    assert html =~ "/observability/benchmarks/scenarios"
  end

  test "benchmark drafts page can approve and reject drafts", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Benchmark draft event finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.benchmark_event"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    assert %{stored: 1, drafts: [draft]} =
             Observability.generate_benchmark_drafts(workspace_id: session.workspace_id)

    {:ok, view, _html} = live(conn, ~p"/observability/benchmarks/drafts")

    assert has_element?(view, "#observability-benchmark-draft-approve-#{draft.id}")

    view
    |> element("#observability-benchmark-draft-approve-#{draft.id}")
    |> render_click()

    assert render(view) =~ "approved"
  end
end
