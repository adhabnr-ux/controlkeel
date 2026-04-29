defmodule ControlKeelWeb.ObservabilityPersistedEvalsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Observability

  test "persisted eval candidates page renders saved candidates", %{conn: conn} do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Persisted eval page finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.persisted_page"
    })

    assert %{stored: 1} = Observability.save_eval_candidates(workspace_id: session.workspace_id)

    {:ok, view, html} = live(conn, ~p"/observability/evals/persisted")

    assert html =~ "Saved eval candidates"
    assert has_element?(view, "#observability-persisted-evals-page")
    assert has_element?(view, "#observability-persisted-evals-count")
    assert has_element?(view, "#observability-persisted-evals-status")
    assert has_element?(view, "#observability-persisted-evals-priority")
    assert has_element?(view, "#observability-persisted-evals-recommendations")
    assert has_element?(view, "#observability-persisted-evals-list")
    assert html =~ "Regression eval for security.persisted_page"
    assert html =~ "human gate true"
  end
end
