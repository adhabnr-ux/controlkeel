defmodule ControlKeelWeb.SessionReviewsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "session reviews lists the reviews for the session", %{conn: conn} do
    session = session_fixture()
    review = review_fixture(%{session: session, submitted_by: "opencode"})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/reviews")

    assert html =~ "Review queue"
    assert html =~ review.title
    assert html =~ "/sessions/#{session.id}/reviews/#{review.id}"
    assert html =~ "plan"
    assert html =~ "pending"
    assert html =~ "opencode"
    assert html =~ "1 total"
    assert html =~ "1 pending"
    assert html =~ "/sessions/#{session.id}"
  end

  test "session reviews shows the task that a review is scoped to", %{conn: conn} do
    session = session_fixture()
    task = task_fixture(%{session: session, title: "Risky plan task"})
    review_fixture(%{session: session, task: task})

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/reviews")

    assert html =~ "Risky plan task"
  end

  test "session reviews shows an empty state", %{conn: conn} do
    session = session_fixture()

    {:ok, _view, html} = live(conn, ~p"/sessions/#{session.id}/reviews")

    assert html =~ "Review queue"
    assert html =~ "No reviews yet."
    assert html =~ "0 total"
    assert html =~ "0 pending"
  end

  test "session reviews updates pending counts after a review is decided", %{conn: conn} do
    session = session_fixture()
    review = review_fixture(%{session: session})

    {:ok, view, html} = live(conn, ~p"/sessions/#{session.id}/reviews")
    assert html =~ "1 pending"
    assert html =~ "pending"

    assert {:ok, _updated} = Mission.respond_review(review, %{"decision" => "approved"})
    send(view.pid, :refresh)

    refreshed_html = render(view)

    assert refreshed_html =~ "0 pending"
    assert refreshed_html =~ "1 resolved"
    assert refreshed_html =~ "approved"
  end

  test "session reviews redirects when the session does not exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Session not found."}}}} =
             live(conn, ~p"/sessions/999999/reviews")
  end
end
