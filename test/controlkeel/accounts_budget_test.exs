defmodule ControlKeel.AccountsBudgetTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.MissionFixtures
  alias ControlKeel.Repo

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, org: org}
  end

  describe "set_org_budget_cents/2 and org_budget_cents/1" do
    test "round-trips the cap", %{org: org} do
      assert nil == Accounts.org_budget_cents(org.id)

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 100_000)
      assert 100_000 == Accounts.org_budget_cents(org.id)
    end

    test "preserves other settings keys", %{org: org} do
      {:ok, _} =
        org
        |> ControlKeel.Accounts.Org.changeset(%{settings: %{"keep_me" => "yes"}})
        |> Repo.update()

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 50_000)
      reloaded = Accounts.get_org(org.id)
      assert reloaded.settings["keep_me"] == "yes"
      assert reloaded.settings["budget_cents"] == 50_000
    end

    test "nil and 0 clear the cap", %{org: org} do
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 100)
      assert 100 == Accounts.org_budget_cents(org.id)

      {:ok, _} = Accounts.set_org_budget_cents(org.id, nil)
      assert nil == Accounts.org_budget_cents(org.id)

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 200)
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 0)
      assert nil == Accounts.org_budget_cents(org.id)
    end

    test "rejects unknown org", %{} do
      assert {:error, :not_found} = Accounts.set_org_budget_cents(999_999, 100)
    end

    test "rejects bad input", %{org: org} do
      assert {:error, :invalid} = Accounts.set_org_budget_cents(org.id, "lots")
    end
  end

  describe "org_spend_cents/1 and org_workspace_breakdown/1" do
    setup %{org: org} do
      ws_a = MissionFixtures.workspace_fixture(%{slug: "ws-a-#{System.unique_integer([:positive])}"})
      ws_b = MissionFixtures.workspace_fixture(%{slug: "ws-b-#{System.unique_integer([:positive])}"})
      ws_unaffil = MissionFixtures.workspace_fixture(%{slug: "ws-solo-#{System.unique_integer([:positive])}"})

      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org.id)

      _s_a = MissionFixtures.session_fixture(%{workspace: ws_a, spent_cents: 300})
      _s_b1 = MissionFixtures.session_fixture(%{workspace: ws_b, spent_cents: 500})
      _s_b2 = MissionFixtures.session_fixture(%{workspace: ws_b, spent_cents: 200})
      _s_solo = MissionFixtures.session_fixture(%{workspace: ws_unaffil, spent_cents: 999})

      {:ok, ws_a: ws_a, ws_b: ws_b, ws_unaffil: ws_unaffil}
    end

    test "sums spend across workspaces in the org only", %{org: org} do
      assert Accounts.org_spend_cents(org.id) == 1000
    end

    test "ignores unaffiliated workspaces", %{org: org, ws_unaffil: solo} do
      total = Accounts.org_spend_cents(org.id)
      refute Repo.get!(ControlKeel.Mission.Workspace, solo.id).org_id == org.id
      assert total == 1000
    end

    test "breakdown is sorted by spend descending", %{org: org, ws_a: ws_a, ws_b: ws_b} do
      rows = Accounts.org_workspace_breakdown(org.id)

      assert Enum.map(rows, & &1.workspace_id) == [ws_b.id, ws_a.id]
      assert Enum.find(rows, &(&1.workspace_id == ws_b.id)).spent_cents == 700
      assert Enum.find(rows, &(&1.workspace_id == ws_a.id)).spent_cents == 300
    end

    test "breakdown includes workspaces with zero spend", %{org: org} do
      empty_ws = MissionFixtures.workspace_fixture(%{slug: "ws-empty-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(empty_ws.id, org.id)

      rows = Accounts.org_workspace_breakdown(org.id)
      empty = Enum.find(rows, &(&1.workspace_id == empty_ws.id))
      assert empty.spent_cents == 0
    end
  end

  describe "org_budget_status/1" do
    test "reports uncapped when no budget set", %{org: org} do
      status = Accounts.org_budget_status(org.id)
      assert status.budget_cents == nil
      assert status.spent_cents == 0
      assert status.remaining_cents == nil
      assert status.over_cap? == false
      assert status.workspace_count == 0
    end

    test "computes remaining and over_cap correctly", %{org: org} do
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-bud-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      _ = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 750})

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1000)

      status = Accounts.org_budget_status(org.id)
      assert status.budget_cents == 1000
      assert status.spent_cents == 750
      assert status.remaining_cents == 250
      assert status.over_cap? == false
      assert status.workspace_count == 1
    end

    test "flags over_cap when spend exceeds budget", %{org: org} do
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-over-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      _ = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 2000})

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1000)

      status = Accounts.org_budget_status(org.id)
      assert status.over_cap? == true
      assert status.remaining_cents == 0
    end
  end
end
