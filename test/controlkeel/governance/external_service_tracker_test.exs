defmodule ControlKeel.Governance.ExternalServiceTrackerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.ExternalServiceTracker
  alias ControlKeel.Mission

  describe "record/1" do
    test "records an external service interaction" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Ext",
          slug: "ext-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Ext Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      assert {:ok, interaction} =
               ExternalServiceTracker.record(%{
                 session_id: session.id,
                 service_name: "github",
                 interaction_type: "api_call",
                 method: "GET",
                 endpoint: "/repos/org/repo/pulls",
                 status_code: 200,
                 latency_ms: 150,
                 cost_cents: 0
               })

      assert interaction.service_name == "github"
      assert interaction.redacted == false
    end

    test "redacts sensitive patterns from endpoints" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Redact",
          slug: "redact-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Redact Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      assert {:ok, interaction} =
               ExternalServiceTracker.record(%{
                 session_id: session.id,
                 service_name: "jira",
                 endpoint: "/rest/api/2/issue?token=abc123secret&email=user@example.com"
               })

      assert interaction.redacted == true
      refute String.contains?(interaction.endpoint, "abc123secret")
      refute String.contains?(interaction.endpoint, "user@example.com")
    end
  end

  describe "summary/1" do
    test "returns aggregated summary" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Sum",
          slug: "sum-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Sum Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      ExternalServiceTracker.record(%{
        session_id: session.id,
        service_name: "github",
        cost_cents: 5
      })

      ExternalServiceTracker.record(%{
        session_id: session.id,
        service_name: "github",
        cost_cents: 3
      })

      ExternalServiceTracker.record(%{
        session_id: session.id,
        service_name: "slack",
        cost_cents: 2
      })

      summary = ExternalServiceTracker.summary(session.id)
      assert summary.total_calls == 3
      assert summary.total_cost_cents == 10
      assert length(summary.services) == 2
    end
  end

  describe "top_services/2" do
    test "returns ranked services" do
      {:ok, workspace} =
        Mission.create_workspace(%{
          name: "Top",
          slug: "top-#{:rand.uniform(10000)}",
          industry: "software",
          agent: "claude-code",
          budget_cents: 10_000,
          compliance_profile: "baseline",
          status: "active"
        })

      {:ok, session} =
        Mission.create_session(%{
          title: "Top Session",
          objective: "Test",
          risk_tier: "low",
          budget_cents: 10_000,
          daily_budget_cents: 5_000,
          workspace_id: workspace.id
        })

      ExternalServiceTracker.record(%{session_id: session.id, service_name: "github"})
      ExternalServiceTracker.record(%{session_id: session.id, service_name: "github"})
      ExternalServiceTracker.record(%{session_id: session.id, service_name: "slack"})

      services = ExternalServiceTracker.top_services(session.id)
      assert length(services) == 2
      assert hd(services).service_name == "github"
    end
  end
end
