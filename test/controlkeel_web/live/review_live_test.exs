defmodule ControlKeelWeb.ReviewLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures
  import Phoenix.LiveViewTest

  alias ControlKeel.Mission

  test "review live renders alignment context from plan refinement", %{conn: conn} do
    session = session_fixture()

    task =
      task_fixture(%{session: session, status: "queued", title: "Collaborative review packet"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Implementation plan with human context",
               "research_summary" => "Mapped review and plan-refinement seams.",
               "alignment_context" => [
                 "PM confirmed the rollout should stay behind approval gates.",
                 "Support asked for reviewer-visible rollback notes before merge."
               ],
               "consulted_roles" => ["PM", "Support", "Security"],
               "options_considered" => ["Patch review packet", "Create separate planning surface"],
               "selected_option" => "Patch review packet",
               "rejected_options" => ["Create separate planning surface"],
               "implementation_steps" => [
                 "Persist alignment fields",
                 "Render them in browser review"
               ],
               "validation_plan" => ["mix test test/controlkeel_web/live/review_live_test.exs"]
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{review.session_id}/reviews/#{review.id}")

    assert html =~ "Human context gathered before execution"
    assert html =~ "PM confirmed the rollout should stay behind approval gates."
    assert html =~ "Support asked for reviewer-visible rollback notes before merge."
    assert html =~ "PM"
    assert html =~ "Support"
    assert html =~ "Security"
  end

  test "review live renders semantic boundary fields from plan refinement", %{conn: conn} do
    task = task_fixture(%{status: "queued", title: "Semantic boundary review"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "plan_phase" => "implementation_plan",
               "submission_body" => "Implementation plan with semantic boundaries",
               "research_summary" => "Mapped review metadata rendering.",
               "options_considered" => ["Render metadata", "Leave MCP-only"],
               "selected_option" => "Render metadata",
               "rejected_options" => ["Leave MCP-only"],
               "implementation_steps" => ["Add card", "Test rendering"],
               "validation_plan" => ["mix test test/controlkeel_web/live/review_live_test.exs"],
               "allowed_semantic_changes" => ["Add review metadata display"],
               "forbidden_semantic_changes" => ["Change execution gating behavior"],
               "invariant_boundaries" => ["Approved plans still gate execution"],
               "requires_reapproval_if" => ["Planner semantics change"],
               "harness_quality_checks" => ["Proof metadata is preserved"]
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{review.session_id}/reviews/#{review.id}")

    assert html =~ "Agent execution guardrails"
    assert html =~ "Allowed semantic changes"
    assert html =~ "Add review metadata display"
    assert html =~ "Forbidden semantic changes"
    assert html =~ "Change execution gating behavior"
    assert html =~ "Invariant boundaries"
    assert html =~ "Approved plans still gate execution"
    assert html =~ "Requires re-approval if"
    assert html =~ "Planner semantics change"
    assert html =~ "Harness quality checks"
    assert html =~ "Proof metadata is preserved"
  end

  test "review live renders respond header controls, textareas, and audit trail timeline", %{
    conn: conn
  } do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Respond UI test"})

    assert {:ok, review} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Plan submission for UI test"
             })

    {:ok, _view, html} = live(conn, ~p"/sessions/#{review.session_id}/reviews/#{review.id}")

    assert html =~ "Respond"
    assert html =~ "Pending"
    assert html =~ "Approve"
    assert html =~ "Deny"
    assert html =~ "Feedback notes"
    assert html =~ "Annotations"
    assert html =~ "placeholder=\"Add notes...\""
    assert html =~ "Audit trail"
    assert html =~ "Submitted"
  end

  test "respond with no review loaded flashes an error instead of raising" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, review: nil, flash: %{}}
    }

    assert {:noreply, socket} =
             ControlKeelWeb.ReviewLive.handle_event(
               "respond",
               %{
                 "review_response" => %{"decision" => "approved"}
               },
               socket
             )

    assert socket.assigns.flash["error"] == "Review not found."
  end

  test "review live renders later resubmissions as revisions", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, status: "queued", title: "Revision rendering"})

    assert {:ok, parent} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Original plan submission",
               "title" => "Original plan"
             })

    assert {:ok, revision} =
             Mission.submit_review(%{
               "task_id" => task.id,
               "review_type" => "plan",
               "submission_body" => "Revised plan submission",
               "title" => "Revised plan",
               "previous_review_id" => parent.id
             })

    {:ok, view, html} = live(conn, ~p"/sessions/#{parent.session_id}/reviews/#{parent.id}")

    assert html =~ "Revisions"
    assert html =~ "Later resubmissions of this review"
    assert html =~ "Revised plan"

    assert view
           |> element("#review-revisions-card a[href*='reviews/#{revision.id}']")
           |> render()

    assert html =~ String.capitalize(revision.status)
  end
end
