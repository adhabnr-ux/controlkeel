defmodule ControlKeelWeb.PolicyStudioLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  setup do
    user = insert_user()
    org = insert_org()
    insert_active_membership(user.id, org.id, "admin")
    org_conn = session_conn(build_conn(), user.id, org.id)
    {:ok, conn: org_conn, org: org}
  end

  test "renders policy packs and rule counts", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Policy Studio"
    assert html =~ "Active governance rules"
    assert html =~ "Baseline"
    assert html =~ "Cost"
    assert html =~ "Active packs"
    assert html =~ "Total rules"
    assert html =~ "Blocking rules"
  end

  test "shows pack descriptions in plain language", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Always active"
    assert html =~ "Detects secrets"
    assert html =~ "budget"
  end

  test "shows empty session state when no sessions exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "No active sessions"
    assert html =~ "/start"
  end

  test "shows session budgets when sessions exist", %{conn: conn, org: org} do
    ws = workspace_fixture(%{org_id: org.id})

    _session =
      session_fixture(%{
        workspace: ws,
        title: "Budget Session",
        budget_cents: 10_000,
        spent_cents: 2_500
      })

    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Budget Session"
    assert html =~ "$100"
    assert html =~ "ck-pill-high"
  end

  test "shows baseline and software policy packs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "Baseline — Secrets"
    assert html =~ "Software — Code hygiene"
    assert html =~ "block"
    assert html =~ "warn"
  end

  test "lists what gets blocked automatically from live pack data", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/policies")

    assert html =~ "What gets blocked automatically"
    # Dynamic blocking rules section shows rule count badge
    assert html =~ "Blocking rules"
    # At least one pack name appears in the blocking rules context
    assert html =~ "Baseline"
    # The section includes guidance text
    assert html =~ "Blocks stop execution"
  end

  # ─────────────── helpers ───────────────

  defp insert_user do
    {:ok, user} =
      %Accounts.User{}
      |> Accounts.User.changeset(%{
        email: "ps-#{System.unique_integer([:positive])}@example.com",
        status: "active"
      })
      |> Repo.insert()

    user
  end

  defp insert_org do
    s = "ps-org-#{System.unique_integer([:positive])}"

    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: s, slug: s, status: "active"})
      |> Repo.insert()

    org
  end

  defp insert_active_membership(user_id, org_id, role) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, _m} =
      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user_id,
        org_id: org_id,
        role: role,
        status: "active",
        accepted_at: now
      })
      |> Repo.insert()
  end

  defp session_conn(conn, user_id, org_id) do
    conn
    |> Plug.Test.init_test_session(%{
      "current_user_id" => user_id,
      "current_org_id" => org_id
    })
  end
end
