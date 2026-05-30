defmodule ControlKeel.Governance.RollbackExecutorTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.RollbackExecutor
  alias ControlKeel.Mission

  describe "checkpoint/3" do
    test "creates a snapshot with the current git HEAD" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Rollback",
          slug: "rollback-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Rollback Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      {:ok, task} =
        Mission.create_task(%{
          title: "Test task",
          status: "queued",
          estimated_cost_cents: 0,
          validation_gate: "none",
          position: 0,
          metadata: %{},
          session_id: session.id
        })

      assert {:ok, snapshot} =
               RollbackExecutor.checkpoint(session.id, task.id, project_root: File.cwd!())

      assert snapshot.status == "available"
      assert snapshot.commit_sha_before != nil
      assert String.length(snapshot.commit_sha_before) >= 7
    end
  end

  describe "execute/4" do
    test "rejects rollback when no snapshot exists" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Exec",
          slug: "exec-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Exec Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      assert {:error, :no_snapshot} == RollbackExecutor.execute(session.id, 999_999)
    end
  end

  describe "status/2 and list/1" do
    test "returns nil when no snapshot exists" do
      assert nil == RollbackExecutor.status(1, 999_999)
    end

    test "lists snapshots for a session" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "List",
          slug: "rlist-#{:rand.uniform(10000)}",
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

      assert [] == RollbackExecutor.list(session.id)
    end
  end
end
