defmodule ControlKeelWeb.ObservabilityCostsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  test "costs page renders local cost and efficiency groups", %{conn: conn} do
    session = session_fixture()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_200,
               cached_input_tokens: 300,
               output_tokens: 240,
               estimated_cost_cents: 16,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    {:ok, view, html} = live(conn, ~p"/observability/costs")

    assert html =~ "Costs and efficiency"
    assert has_element?(view, "#observability-costs-page")
    assert has_element?(view, "#observability-costs-total")
    assert has_element?(view, "#observability-costs-summary")
    assert has_element?(view, "#observability-costs-recommendations")
    assert has_element?(view, "#observability-costs-groups")
    assert has_element?(view, "#observability-costs-by-model")
    assert has_element?(view, "#observability-costs-by-tool")
    assert has_element?(view, "#observability-costs-by-source")
    assert has_element?(view, "#observability-costs-by-provider")
    assert html =~ "gpt-5.5"
    assert html =~ "ck_validate"
    assert html =~ "codex-cli"
    assert html =~ "openai"
  end
end
