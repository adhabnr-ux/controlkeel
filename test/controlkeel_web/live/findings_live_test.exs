defmodule ControlKeelWeb.FindingsLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission

  test "findings browser supports filter combinations and mission links", %{conn: conn} do
    alpha = session_fixture(%{title: "Alpha mission"})
    bravo = session_fixture(%{title: "Bravo mission"})

    target =
      finding_fixture(%{
        session: alpha,
        title: "Alpha SQL finding",
        rule_id: "security.sql_injection",
        category: "security",
        severity: "high",
        status: "open",
        plain_message: "Alpha query issue",
        metadata: %{"path" => "lib/query_builder.js"}
      })

    _other =
      finding_fixture(%{
        session: bravo,
        title: "Bravo XSS finding",
        rule_id: "security.xss_unsafe_html",
        category: "security",
        severity: "medium",
        status: "approved",
        plain_message: "Bravo browser issue"
      })

    {:ok, view, html} =
      live(
        conn,
        ~p"/findings?#{%{q: "Alpha", severity: "high", status: "open", category: "security", session_id: alpha.id}}"
      )

    assert html =~ "Findings browser"
    assert html =~ "Alpha SQL finding"
    refute html =~ "Bravo XSS finding"
    assert has_element?(view, "a[href=\"/sessions/#{alpha.id}\"]", alpha.title)

    patched =
      render_change(
        form(view, "form",
          filters: %{
            "q" => "Bravo",
            "severity" => "",
            "status" => "",
            "category" => "",
            "session_id" => ""
          }
        )
      )

    assert patched =~ "Findings browser"
    assert_patch(view, ~p"/findings?#{%{q: "Bravo"}}")

    _ = target
  end

  test "findings browser paginates and updates status actions live", %{conn: conn} do
    session = session_fixture()

    Enum.each(1..21, fn index ->
      finding_fixture(%{
        session: session,
        title: "Paged finding #{index}",
        rule_id: "security.sample.#{index}",
        severity: "low",
        category: "ops",
        status: "open"
      })
    end)

    actionable =
      finding_fixture(%{
        session: session,
        title: "Actionable finding",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open",
        metadata: %{"path" => "lib/query_builder.js"}
      })

    rejectable =
      finding_fixture(%{
        session: session,
        title: "Rejectable finding",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    {:ok, view, html} = live(conn, ~p"/findings")
    assert html =~ "Page 1 of 3"
    assert has_element?(view, "a[href*=\"page=2\"]", "Next")

    # Open the guided-fix modal then approve from the modal footer
    render_click(
      element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{actionable.id}\"]")
    )

    render_click(
      element(view, "button[phx-click=\"approve\"][phx-value-id=\"#{actionable.id}\"]")
    )

    assert render(view) =~ "Finding approved."
    assert Mission.get_finding!(actionable.id).status == "approved"

    # Approve keeps the modal open showing the updated status
    assert render(view) =~ "Guided fix"
    assert render(view) =~ "approved"

    # Open the modal for the rejectable finding then reject from the footer
    render_click(
      element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{rejectable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"reject\"][phx-value-id=\"#{rejectable.id}\"]"))

    # Confirm the rejection (without a reason)
    render_click(element(view, "button[phx-click=\"confirm_reject\"]"))
    assert render(view) =~ "Finding rejected."
    assert Mission.get_finding!(rejectable.id).status == "rejected"
  end

  test "findings browser stores and displays rejection reason", %{conn: conn} do
    session = session_fixture()

    rejectable =
      finding_fixture(%{
        session: session,
        title: "Rejectable with reason",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    # Open the guided-fix modal then reject
    render_click(
      element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{rejectable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"reject\"][phx-value-id=\"#{rejectable.id}\"]"))

    # Type a rejection reason via the set_reject_reason event
    render_click(view, "set_reject_reason", %{"value" => "False positive on legacy code"})

    # Confirm the rejection
    render_click(element(view, "button[phx-click=\"confirm_reject\"]"))

    finding = Mission.get_finding!(rejectable.id)
    assert finding.status == "rejected"
    assert finding.metadata["rejection_reason"] == "False positive on legacy code"

    # The reason should be visible on the rejected finding's card
    assert render(view) =~ "False positive on legacy code"
  end

  test "findings browser escalates an active finding from the fix modal", %{conn: conn} do
    session = session_fixture()

    open_finding =
      finding_fixture(%{
        session: session,
        title: "Escalatable finding",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open"
      })

    approved =
      finding_fixture(%{
        session: session,
        title: "Approved finding",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "approved"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    # No modal is open, so no decision buttons are on the page
    refute has_element?(view, "button[phx-click=\"escalate\"]")

    render_click(element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{approved.id}\"]"))

    # Escalate only appears for active (open/blocked) findings, not settled ones
    refute has_element?(view, "button[phx-click=\"escalate\"]")

    render_click(element(view, "button[phx-click=\"close_fix\"][class~=\"bg-overlay\"]"))

    render_click(
      element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{open_finding.id}\"]")
    )

    assert has_element?(view, "button[phx-click=\"escalate\"]")

    render_click(element(view, "button[phx-click=\"escalate\"]"))

    assert render(view) =~ "Finding escalated."
    assert Mission.get_finding!(open_finding.id).status == "escalated"
  end

  test "findings browser filters by vulnerability-case metadata", %{conn: conn} do
    session = session_fixture()

    patched =
      finding_fixture(%{
        session: session,
        title: "Patched case",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open",
        metadata: %{
          "finding_family" => "vulnerability_case",
          "patch_status" => "merged",
          "disclosure_status" => "public",
          "maintainer_scope" => "first_party"
        }
      })

    _draft =
      finding_fixture(%{
        session: session,
        title: "Draft case",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open",
        metadata: %{
          "finding_family" => "vulnerability_case",
          "patch_status" => "none",
          "disclosure_status" => "draft",
          "maintainer_scope" => "third_party_vendor"
        }
      })

    {:ok, view, _html} =
      live(conn, ~p"/findings?#{%{patch_status: "merged"}}")

    assert render(view) =~ "Patched case"
    refute render(view) =~ "Draft case"

    patched_change =
      render_change(
        form(view, "form",
          filters: %{
            "q" => "",
            "severity" => "",
            "status" => "",
            "category" => "",
            "session_id" => "",
            "patch_status" => "",
            "disclosure_status" => "draft",
            "maintainer_scope" => "third_party_vendor"
          }
        )
      )

    assert patched_change =~ "Draft case"
    refute patched_change =~ "Patched case"

    assert_patch(
      view,
      ~p"/findings?#{%{disclosure_status: "draft", maintainer_scope: "third_party_vendor"}}"
    )

    _ = patched
  end

  test "findings browser renders the guided fix panel", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "SQL finding",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        metadata: %{"path" => "lib/query_builder.js", "matched_text_redacted" => "OR 1... --"}
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    detail_html =
      render_click(
        element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{finding.id}\"]")
      )

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "parameterized queries"
    assert detail_html =~ "Copy fix prompt"
  end

  test "findings browser modal decision guards hide settled actions", %{conn: conn} do
    session = session_fixture()

    approved =
      finding_fixture(%{
        session: session,
        title: "Approved guard",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "approved"
      })

    rejected =
      finding_fixture(%{
        session: session,
        title: "Rejected guard",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "rejected"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    render_click(element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{approved.id}\"]"))

    refute has_element?(view, "button[phx-click=\"approve\"]")
    refute has_element?(view, "button[phx-click=\"escalate\"]")
    assert has_element?(view, "button[phx-click=\"reject\"]")

    render_click(element(view, "button[phx-click=\"close_fix\"][class~=\"bg-overlay\"]"))

    render_click(element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{rejected.id}\"]"))

    refute has_element?(view, "button[phx-click=\"reject\"]")
    assert has_element?(view, "button[phx-click=\"approve\"]")
  end

  test "findings browser advanced filters are hidden by default and toggle open", %{conn: conn} do
    session = session_fixture()
    finding_fixture(%{session: session, title: "Toggle me", status: "open"})

    {:ok, view, html} = live(conn, ~p"/findings")

    assert html =~ "More filters"
    refute html =~ "Fewer filters"

    render_click(element(view, "button[phx-click=\"toggle_more_filters\"]"))
    assert render(view) =~ "Fewer filters"

    render_click(element(view, "button[phx-click=\"toggle_more_filters\"]"))
    assert render(view) =~ "More filters"
  end

  test "findings browser auto-opens advanced filters and counts active ones", %{conn: conn} do
    session = session_fixture()
    finding_fixture(%{session: session, title: "Autopen", status: "open"})

    {:ok, view, html} = live(conn, ~p"/findings?#{%{patch_status: "merged"}}")

    assert html =~ "Fewer filters"

    render_click(element(view, "button[phx-click=\"toggle_more_filters\"]"))

    assert render(view) =~ "More filters (1 active)"
  end

  test "web-initiated finding actions record web actor attribution on audit events", %{conn: conn} do
    session = session_fixture()

    finding =
      finding_fixture(%{
        session: session,
        title: "Actor tracked",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open"
      })

    escalated =
      finding_fixture(%{
        session: session,
        title: "Escalated actor tracked",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    render_click(element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{finding.id}\"]"))

    render_click(element(view, "button[phx-click=\"approve\"][phx-value-id=\"#{finding.id}\"]"))

    event = Mission.finding_audit_events(finding.id) |> List.last()
    assert event.actor_source == "web"
    assert event.actor_identifier == "web"

    render_click(element(view, "button[phx-click=\"close_fix\"][class~=\"bg-overlay\"]"))

    render_click(
      element(view, "button[phx-click=\"view_fix\"][phx-value-id=\"#{escalated.id}\"]")
    )

    render_click(
      element(view, "button[phx-click=\"escalate\"][phx-value-id=\"#{escalated.id}\"]")
    )

    event = Mission.finding_audit_events(escalated.id) |> List.last()
    assert event.event_type == "escalated"
    assert event.actor_source == "web"
  end
end
