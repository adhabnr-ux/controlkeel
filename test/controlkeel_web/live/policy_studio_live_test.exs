defmodule ControlKeelWeb.PolicyStudioLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts

  test "toggle_pack ignores unknown pack names", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    before_click = render(view)
    render_click(view, "toggle_pack", %{"name" => "not-a-real-pack"})

    assert render(view) == before_click
  end

  test "toggle_pack expands and collapses baseline pack", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_packs_dialog")

    trigger = element(view, "button[phx-value-name=\"baseline\"]")
    render_click(trigger)

    assert render(view) =~ "Detects secrets, injection, and XSS"

    render_click(trigger)

    refute render(view) =~ "Detects secrets, injection, and XSS"
  end

  test "shows empty policy-sets state when none exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "No custom policy sets yet"
  end

  test "lists policy sets with status, rule count, and workspace assignments", %{conn: conn} do
    {:ok, set} =
      ControlKeel.Platform.create_policy_set(%{
        "name" => "no-rm-rf",
        "description" => "Block destructive deletes",
        "rules" => [
          %{
            "id" => "shell.destructive_rm_rf",
            "category" => "security",
            "severity" => "critical",
            "action" => "block",
            "plain_message" => "blocked",
            "matcher" => %{"type" => "regex", "patterns" => ["rm -rf"]}
          }
        ]
      })

    {:ok, workspace} = Accounts.create_org(%{name: "Org A", slug: "test-org-a"})
    ws = workspace_fixture(%{org_id: workspace.id})
    {:ok, _assignment} = ControlKeel.Platform.apply_policy_set(ws.id, set.id, %{precedence: 10})
    {:ok, view, html} = live(conn, ~p"/policies")

    assert html =~ "no-rm-rf"
    assert html =~ "active"
    assert html =~ "1 rules"
    assert html =~ "Block destructive deletes"
    assert html =~ "workspace ##{ws.id}"
    assert html =~ "precedence 10"
    assert has_element?(view, "span[title='block, security']", "destructive rm rf")
  end

  test "lists disabled assignments with a marker", %{conn: conn} do
    {:ok, set} =
      ControlKeel.Platform.create_policy_set(%{
        "name" => "paused-set",
        "description" => "Paused controls",
        "rules" => [
          %{
            "id" => "cost.overrun",
            "category" => "cost",
            "severity" => "high",
            "action" => "warn",
            "plain_message" => "over budget",
            "matcher" => %{"type" => "budget", ratio_gte: 1.0}
          }
        ]
      })

    {:ok, org} = Accounts.create_org(%{name: "Paused Org", slug: "paused-org"})
    ws = workspace_fixture(%{org_id: org.id})
    {:ok, _} = ControlKeel.Platform.apply_policy_set(ws.id, set.id, %{"enabled" => false})

    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "paused-set"
    assert html =~ "workspace ##{ws.id}"
    assert html =~ ", disabled"
  end

  test "block count badge shows destructive class", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "bg-destructive/10"
  end

  test "warn rules show warning class when pack is expanded", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_packs_dialog")
    render_click(element(view, "button[phx-value-name=\"software\"]"))

    assert render(view) =~ "bg-warning/10"
  end

  test "renders pack labels for known domain packs", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/policies")

    refute html =~ "Baseline"

    render_click(view, "open_packs_dialog")
    html = render(view)

    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Software"
  end

  test "new policy set button opens the create modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    refute has_element?(view, "#policy-set-form")

    render_click(view, "open_create_modal")

    assert has_element?(view, "#policy-set-form")
    assert has_element?(view, "#policy-set-create-modal-title")
    assert render(view) =~ "New policy set"
  end

  test "creating a policy set from the modal saves it and lists it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")

    rules_json =
      ~s|[{"id": "shell.destructive_rm_rf", "category": "security", "severity": "critical", "action": "block", "plain_message": "blocked", "matcher": {"type": "regex", "patterns": ["rm -rf"]}}]|

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{
        "name" => "no-rm-rf-web",
        "scope" => "workspace",
        "description" => "Block destructive deletes from web",
        "rules_json" => rules_json
      }
    })

    html = render(view)

    assert html =~ "Created policy set #"
    assert html =~ "no-rm-rf-web"

    assert Enum.any?(ControlKeel.Platform.list_policy_sets(), &(&1.name == "no-rm-rf-web"))
  end

  test "wrapped entries JSON is accepted like the CLI rules file format", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")

    entries =
      ~s|{"entries": [{"id": "cost.overrun", "category": "cost", "severity": "high", "action": "warn", "plain_message": "over budget", "matcher": {"type": "budget", "ratio_gte": 1.0}}]}|

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{
        "name" => "budget-warn-web",
        "scope" => "global",
        "description" => nil,
        "rules_json" => entries
      }
    })

    assert render(view) =~ "budget-warn-web"

    set = Enum.find(ControlKeel.Platform.list_policy_sets(), &(&1.name == "budget-warn-web"))
    assert length(ControlKeel.Platform.PolicySet.rule_entries(set)) == 1
  end

  test "invalid rules JSON keeps the modal open with an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{
        "name" => "broken-json",
        "scope" => "workspace",
        "rules_json" => "{not json"
      }
    })

    html = render(view)

    assert has_element?(view, "#policy-set-form")
    assert html =~ "invalid JSON"
    refute Enum.any?(ControlKeel.Platform.list_policy_sets(), &(&1.name == "broken-json"))
  end

  test "non-array rules JSON shows a shape error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")

    render_change(view, "validate_policy_set", %{
      "policy_set" => %{"name" => "shape-check", "rules_json" => "{\"id\": \"one-object\"}"}
    })

    assert render(view) =~ "must be an array of rule entries"
  end

  test "missing name shows validation error without saving", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")

    render_submit(view, "save_policy_set", %{
      "policy_set" => %{"name" => "", "scope" => "workspace", "rules_json" => ""}
    })

    html = render(view)

    assert has_element?(view, "#policy-set-form")
    assert html =~ "can&#39;t be blank"
    assert ControlKeel.Platform.list_policy_sets() == []
  end

  test "cancel closes the create modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")
    assert has_element?(view, "#policy-set-form")

    render_click(view, "close_create_modal")

    refute has_element?(view, "#policy-set-form")
  end

  test "escape closes the packs dialog", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_packs_dialog")
    assert has_element?(view, "#packs-dialog")

    view |> element("#packs-dialog") |> render_keydown(%{"key" => "escape"})

    refute has_element?(view, "#packs-dialog")
  end

  test "escape closes the create modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/policies")

    render_click(view, "open_create_modal")
    assert has_element?(view, "#policy-set-form")

    view |> element("#policy-set-create-modal") |> render_keydown(%{"key" => "escape"})

    refute has_element?(view, "#policy-set-form")
  end
end
