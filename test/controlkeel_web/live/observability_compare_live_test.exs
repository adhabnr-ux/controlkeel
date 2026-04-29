defmodule ControlKeelWeb.ObservabilityCompareLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  test "compare page renders invocation comparison groups", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 800,
               output_tokens: 250,
               estimated_cost_cents: 10,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    {:ok, view, html} = live(conn, ~p"/observability/compare")

    assert html =~ "Compare invocations"
    assert has_element?(view, "#observability-compare-page")
    assert has_element?(view, "#observability-compare-total")
    assert has_element?(view, "#observability-compare-summary")
    assert has_element?(view, "#observability-compare-recommendations")
    assert has_element?(view, "#observability-compare-groups")
    assert has_element?(view, "#observability-compare-by-source")
    assert has_element?(view, "#observability-compare-by-model")
    assert has_element?(view, "#observability-compare-by-provider")
    assert has_element?(view, "#observability-compare-by-tool")
    assert html =~ "codex-cli"
    assert html =~ "gpt-5.5"
    assert html =~ "openai"
    assert html =~ "ck_validate"
  end
end
