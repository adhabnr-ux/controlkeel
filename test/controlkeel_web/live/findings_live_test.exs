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
    assert html =~ "Page 1 of 2"
    assert has_element?(view, "a[href*=\"page=2\"]", "Next")

    # Open 3-dot menu then click approve
    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{actionable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"approve\"]"))

    assert render(view) =~ "Finding approved."
    assert Mission.get_finding!(actionable.id).status == "approved"

    # Open 3-dot menu then click reject
    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{rejectable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"reject\"]"))
    # Confirm the rejection (without a reason)
    render_click(element(view, "button[phx-click=\"confirm_reject\"]"))
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

    # Open dropdown and click reject
    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{rejectable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"reject\"]"))

    # Type a rejection reason via the set_reject_reason event
    render_click(view, "set_reject_reason", %{"value" => "False positive on legacy code"})

    # Confirm the rejection
    render_click(element(view, "button[phx-click=\"confirm_reject\"]"))

    finding = Mission.get_finding!(rejectable.id)
    assert finding.status == "rejected"
    assert finding.metadata["rejection_reason"] == "False positive on legacy code"

    # The reason should be visible in the findings table
    assert render(view) =~ "False positive on legacy code"
  end

  test "findings browser escalates an active finding from the row menu", %{conn: conn} do
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

    # Escalate only appears for active (open/blocked) findings, not settled ones
    refute has_element?(view, "button[phx-click=\"escalate\"]")

    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{approved.id}\"]")
    )

    refute has_element?(view, "button[phx-click=\"escalate\"]")

    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{open_finding.id}\"]")
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

    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{finding.id}\"]")
    )

    detail_html =
      render_click(element(view, "button[phx-click=\"view_fix\"]"))

    assert detail_html =~ "Guided fix"
    assert detail_html =~ "parameterized queries"
    assert detail_html =~ "Copy fix prompt"
  end

  test "findings browser bulk-resolves and bulk-dismisses selected findings", %{conn: conn} do
    session = session_fixture()

    first =
      finding_fixture(%{
        session: session,
        title: "Bulk resolve me",
        rule_id: "security.sql_injection",
        severity: "high",
        category: "security",
        status: "open"
      })

    second =
      finding_fixture(%{
        session: session,
        title: "Bulk dismiss me",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    settled =
      finding_fixture(%{
        session: session,
        title: "Already approved",
        rule_id: "security.csp_inline_script",
        severity: "medium",
        category: "security",
        status: "approved"
      })

    dismissable =
      finding_fixture(%{
        session: session,
        title: "Dismiss with reason",
        rule_id: "security.loose_tls_cert",
        severity: "low",
        category: "ops",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    refute has_element?(view, "button[phx-click=\"open_bulk\"]")

    render_click(
      element(view, "input[phx-click=\"toggle_select\"][phx-value-id=\"#{first.id}\"]")
    )

    render_click(
      element(view, "input[phx-click=\"toggle_select\"][phx-value-id=\"#{second.id}\"]")
    )

    assert has_element?(view, "button[phx-click=\"open_bulk\"][phx-value-action=\"resolve\"]")
    assert render(view) =~ "finding(s) selected"

    render_click(element(view, "button[phx-click=\"open_bulk\"][phx-value-action=\"resolve\"]"))

    assert has_element?(view, "button[phx-click=\"confirm_bulk\"]")
    assert render(view) =~ "Resolve findings"

    render_click(element(view, "button[phx-click=\"confirm_bulk\"]"))

    assert Mission.get_finding!(first.id).status == "approved"
    assert Mission.get_finding!(second.id).status == "approved"
    assert Mission.get_finding!(settled.id).status == "approved"
    assert Mission.get_finding!(dismissable.id).status == "open"

    refute has_element?(view, "button[phx-click=\"open_bulk\"]")

    # Bulk dismiss records an optional reason
    render_click(
      element(view, "input[phx-click=\"toggle_select\"][phx-value-id=\"#{dismissable.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"open_bulk\"][phx-value-action=\"dismiss\"]"))

    assert render(view) =~ "Dismiss findings"

    render_click(view, "set_bulk_reason", %{"value" => "Duplicate of CK-123"})
    render_click(element(view, "button[phx-click=\"confirm_bulk\"]"))

    dismissed = Mission.get_finding!(dismissable.id)
    assert dismissed.status == "rejected"
    assert dismissed.metadata["rejection_reason"] == "Duplicate of CK-123"
  end

  test "findings browser select-page checkbox selects and clears the page", %{conn: conn} do
    session = session_fixture()

    finding = finding_fixture(%{session: session, title: "One", status: "open"})
    other = finding_fixture(%{session: session, title: "Two", status: "open"})

    {:ok, view, _html} = live(conn, ~p"/findings")

    render_click(element(view, "input[phx-click=\"select_page\"]"))

    assert render(view) =~ "finding(s) selected"

    render_click(element(view, "input[phx-click=\"select_page\"]"))

    refute has_element?(view, "button[phx-click=\"open_bulk\"]")

    # Individual toggle still works
    render_click(
      element(view, "input[phx-click=\"toggle_select\"][phx-value-id=\"#{finding.id}\"]")
    )

    assert render(view) =~ "finding(s) selected"

    render_click(element(view, "button[phx-click=\"clear_selection\"]"))
    refute has_element?(view, "button[phx-click=\"open_bulk\"]")

    _ = other
  end

  test "web-disposed findings record web actor attribution on audit events", %{conn: conn} do
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
        title: "Bulk actor tracked",
        rule_id: "security.xss_unsafe_html",
        severity: "medium",
        category: "security",
        status: "open"
      })

    {:ok, view, _html} = live(conn, ~p"/findings")

    render_click(
      element(view, "button[phx-click=\"toggle_dropdown\"][phx-value-id=\"#{finding.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"approve\"]"))

    event = Mission.finding_audit_events(finding.id) |> List.last()
    assert event.actor_source == "web"
    assert event.actor_identifier == "web"

    render_click(
      element(view, "input[phx-click=\"toggle_select\"][phx-value-id=\"#{escalated.id}\"]")
    )

    render_click(element(view, "button[phx-click=\"open_bulk\"][phx-value-action=\"escalate\"]"))

    render_click(element(view, "button[phx-click=\"confirm_bulk\"]"))

    event = Mission.finding_audit_events(escalated.id) |> List.last()
    assert event.event_type == "escalated"
    assert event.actor_source == "web"
  end
end
