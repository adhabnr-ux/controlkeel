defmodule ControlKeelWeb.OnboardingLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "user can complete onboarding, regenerate, and create a mission", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/missions/start")

    assert html =~ "Choose the domain and primary agent"
    assert html =~ "Founder / Product Builder"

    assert render_submit(
             form(view, "form", launch: %{"occupation" => "healthcare", "agent" => "claude"})
           ) =~ "Describe the product"

    assert render_submit(
             form(view, "form",
               launch: %{
                 "project_name" => "Clinic Intake",
                 "idea" =>
                   "Build a patient intake workflow for a small clinic with staff review and exports."
               }
             )
           ) =~ "Answer the guided interview"

    review_html =
      render_submit(
        form(view, "form",
          launch: %{
            "interview_answers" => %{
              "who_uses_it" => "Front desk staff and clinic admins",
              "data_involved" => "Patient names, insurance notes, scheduling details",
              "first_release" => "Intake form, review queue, export",
              "constraints" => "Local-first deploy, approval before production"
            }
          }
        )
      )

    assert review_html =~ "Review the compiled brief"
    assert review_html =~ "Acceptance criteria"
    assert review_html =~ "Production boundary"
    assert review_html =~ "Local-first deploy"
    assert review_html =~ "approval before production"
    assert Mission.list_sessions() == []

    regenerated_html = render_click(element(view, "button[phx-click=\"regenerate\"]"))
    assert regenerated_html =~ "Review the compiled brief"
    assert Mission.list_sessions() == []

    render_click(element(view, "button[phx-click=\"accept\"]"))
    {path, _flash} = assert_redirect(view)

    assert path =~ "/missions/"

    redirected_html =
      conn
      |> Phoenix.ConnTest.recycle()
      |> get(path)
      |> html_response(200)

    assert redirected_html =~ "Mission control"
    assert length(Mission.list_sessions()) == 1
  end

  test "validation errors render and provider keys are not exposed in the browser", %{conn: conn} do
    original = Application.get_env(:controlkeel, ControlKeel.Intent)

    on_exit(fn ->
      if original do
        Application.put_env(:controlkeel, ControlKeel.Intent, original)
      else
        Application.delete_env(:controlkeel, ControlKeel.Intent)
      end
    end)

    Application.put_env(
      :controlkeel,
      ControlKeel.Intent,
      %{
        providers: %{
          openai: %{api_key: "sk-secret-test", base_url: "http://127.0.0.1:1", model: "gpt-5.4"}
        }
      }
    )

    {:ok, view, html} = live(conn, ~p"/missions/start")
    refute html =~ "sk-secret-test"

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    error_html =
      render_submit(form(view, "form", launch: %{"project_name" => "Tiny", "idea" => "short"}))

    assert error_html =~ "Describe the product in a few concrete sentences (at least 12 characters)."
    refute error_html =~ "sk-secret-test"
  end

  test "review step explains heuristic mode and provider status without leaking secrets", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/missions/start")

    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    render_submit(
      form(view, "form",
        launch: %{
          "project_name" => "Ops Console",
          "idea" =>
            "Build an internal ops console with approvals, audit notes, and delivery tracking."
        }
      )
    )

    review_html =
      render_submit(
        form(view, "form",
          launch: %{
            "interview_answers" => %{
              "who_uses_it" => "Operators and engineering leads",
              "data_involved" => "Internal ticket metadata, release notes, and approval history",
              "first_release" => "Dashboard, approvals, searchable notes",
              "constraints" => "Local-first setup, no API key required for first run"
            }
          }
        )
      )

    assert review_html =~ "Compiler Info"
    assert review_html =~ "Objective"
    assert review_html =~ "Acceptance criteria"
    assert review_html =~ "Production boundary"
    assert review_html =~ "Open Questions"
    refute review_html =~ "sk-secret-test"
  end

  test "expanded domain occupations render and advance through onboarding", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/missions/start")

    assert has_element?(view, "option[value=\"hr\"]")
    assert has_element?(view, "option[value=\"legal\"]")
    assert has_element?(view, "option[value=\"marketing\"]")
    assert has_element?(view, "option[value=\"sales\"]")
    assert has_element?(view, "option[value=\"realestate\"]")
    assert has_element?(view, "option[value=\"government\"]")
    assert has_element?(view, "option[value=\"insurance\"]")
    assert has_element?(view, "option[value=\"ecommerce\"]")
    assert has_element?(view, "option[value=\"logistics\"]")
    assert has_element?(view, "option[value=\"manufacturing\"]")
    assert has_element?(view, "option[value=\"nonprofit\"]")

    next_html =
      render_submit(
        form(view, "form", launch: %{"occupation" => "marketing", "agent" => "claude"})
      )

    assert next_html =~ "Describe the product"
    assert next_html =~ "Marketing / Content"
  end

  test "onboarding UI prevents duplicate project names", %{conn: conn} do
    workspace = workspace_fixture(%{name: "Existing Project"})
    _session = session_fixture(%{workspace: workspace, title: "Existing Project"})

    {:ok, view, _html} = live(conn, ~p"/missions/start")

    # Step 1
    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    # Step 2: Attempting to submit a duplicate project name
    error_html =
      render_submit(
        form(view, "form",
          launch: %{
            "project_name" => "Existing Project",
            "idea" => "Build a new portal with workflow."
          }
        )
      )

    assert error_html =~ "This project name is already used by an existing mission."
  end

  test "user can continue from an existing mission in onboarding", %{conn: conn} do
    session =
      session_fixture(%{
        title: "Saved Project",
        objective: "Original project objective",
        execution_brief: %{
          "idea" => "Original project objective",
          "compiler" => %{
            "interview_answers" => %{
              "who_uses_it" => "Original users",
              "constraints" => "Original constraints"
            }
          }
        }
      })

    {:ok, view, _html} = live(conn, ~p"/missions/start")

    # Step 1
    render_submit(form(view, "form", launch: %{"occupation" => "founder", "agent" => "claude"}))

    # Step 2: Select the existing mission from dropdown
    render_change(view, :select_mission, %{recent_mission_id: to_string(session.id)})

    # Verify project name is populated
    assert has_element?(view, "input[name=\"launch[project_name]\"][value=\"Saved Project\"]")
    assert render(view) =~ "Original project objective"
  end
end
