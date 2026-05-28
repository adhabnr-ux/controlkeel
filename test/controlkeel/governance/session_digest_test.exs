defmodule ControlKeel.Governance.SessionDigestTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.SessionDigest
  alias ControlKeel.Mission

  describe "generate/2" do
    test "creates a session digest with correct counts" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Test",
          slug: "test-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Test Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      assert {:ok, digest} = SessionDigest.generate(session.id)
      assert digest.session_id == session.id
      assert digest.digest_type == "session"
      assert digest.needs_attention == false
      assert digest.tasks_completed == 0
      assert digest.findings_raised == 0
    end

    test "flags needs_attention when budget is over 80%" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Broke",
          slug: "broke-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Broke Session",
          objective: "Spend",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          spent_cents: 9_000,
          workspace_id: workspace.id
        })

      assert {:ok, digest} = SessionDigest.generate(session.id)
      assert digest.needs_attention == true
    end
  end

  describe "latest/1" do
    test "returns the most recent digest" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Latest",
          slug: "latest-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Latest Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      {:ok, _first} = SessionDigest.generate(session.id)
      {:ok, second} = SessionDigest.generate(session.id)

      assert ^second = SessionDigest.latest(session.id)
    end
  end

  describe "list/2" do
    test "returns digests newest first" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "List",
          slug: "list-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "List Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      {:ok, _first} = SessionDigest.generate(session.id)
      {:ok, _second} = SessionDigest.generate(session.id)

      digests = SessionDigest.list(session.id)
      assert length(digests) == 2
    end
  end
end
