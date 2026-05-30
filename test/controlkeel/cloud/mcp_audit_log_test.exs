defmodule ControlKeel.Cloud.McpAuditLogTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Cloud.McpAuditLog
  alias ControlKeel.Cloud.McpToolCall
  alias ControlKeel.ProtocolInterop
  alias ControlKeel.Repo

  describe "record/2 direct" do
    test "persists an allowed call with workspace + service account from auth context" do
      workspace = workspace_fixture()

      %{service_account: account, token: _token} =
        service_account_fixture(%{workspace_id: workspace.id})

      auth_context = %{
        service_account: account,
        scopes: ["mcp:access", "context:read"]
      }

      :ok =
        McpAuditLog.record(:allowed, %{
          service_account: account,
          tool_name: "ck_context",
          resource: "mcp",
          arguments: %{"session_id" => 1, "project_root" => "/abs/path"},
          scopes: auth_context.scopes
        })

      [row] = Repo.all(McpToolCall)
      assert row.workspace_id == workspace.id
      assert row.service_account_id == account.id
      assert row.tool_name == "ck_context"
      assert row.resource == "mcp"
      assert row.outcome == "allowed"
      assert row.scopes_granted == "mcp:access,context:read"
      assert row.argument_keys == "project_root,session_id"
      assert row.denial_reason == nil
    end

    test "persists a denied call with reason" do
      :ok =
        McpAuditLog.record(:denied, %{
          tool_name: "ck_finding",
          resource: "mcp",
          arguments: %{"finding_id" => 1},
          denial_reason: "invalid_scope"
        })

      [row] = Repo.all(McpToolCall)
      assert row.outcome == "denied"
      assert row.denial_reason == "invalid_scope"
      assert row.workspace_id == nil
    end

    test "argument_keys are sorted and capped" do
      args =
        Enum.into(1..30, %{}, fn n ->
          {"k#{String.pad_leading("#{n}", 2, "0")}", n}
        end)

      :ok =
        McpAuditLog.record(:allowed, %{tool_name: "ck_context", resource: "mcp", arguments: args})

      [row] = Repo.all(McpToolCall)
      keys = String.split(row.argument_keys, ",")
      assert length(keys) <= 16
      assert keys == Enum.sort(keys)
    end

    test "is fail-soft: invalid attrs do not raise" do
      assert :ok = McpAuditLog.record(:allowed, %{tool_name: nil})
      assert Repo.aggregate(McpToolCall, :count, :id) == 0
    end
  end

  describe "ProtocolInterop integration" do
    setup do
      workspace = workspace_fixture()

      %{service_account: account, token: _token} =
        service_account_fixture(%{workspace_id: workspace.id})

      {:ok, account: account, workspace: workspace}
    end

    test "authorize_hosted_tool_call records a denied entry when scopes are missing", %{
      account: account
    } do
      auth_context = %{
        service_account: account,
        scopes: ["mcp:access"],
        resource_access_id: "mcp"
      }

      result =
        ProtocolInterop.authorize_hosted_tool_call(
          auth_context,
          "ck_context",
          %{"session_id" => 1},
          "mcp"
        )

      assert {:error, _} = result

      [row] = Repo.all(McpToolCall)
      assert row.outcome == "denied"
      assert row.tool_name == "ck_context"
      assert row.resource == "mcp"
      assert is_binary(row.denial_reason)
    end
  end

  describe "aggregations" do
    test "summary/0 returns totals by outcome" do
      :ok = McpAuditLog.record(:allowed, %{tool_name: "ck_context", resource: "mcp"})
      :ok = McpAuditLog.record(:allowed, %{tool_name: "ck_context", resource: "mcp"})

      :ok =
        McpAuditLog.record(:denied, %{
          tool_name: "ck_finding",
          resource: "mcp",
          denial_reason: "invalid_scope"
        })

      assert McpAuditLog.global_summary() == %{total: 3, allowed: 2, denied: 1}
    end

    test "counts_by_tool/0 groups by tool with outcome split" do
      :ok = McpAuditLog.record(:allowed, %{tool_name: "ck_context", resource: "mcp"})

      :ok =
        McpAuditLog.record(:denied, %{
          tool_name: "ck_context",
          resource: "mcp",
          denial_reason: "x"
        })

      :ok = McpAuditLog.record(:allowed, %{tool_name: "ck_finding", resource: "mcp"})

      counts = McpAuditLog.global_counts_by_tool()
      ck_context = Enum.find(counts, &(&1.tool_name == "ck_context"))
      ck_finding = Enum.find(counts, &(&1.tool_name == "ck_finding"))

      assert ck_context.allowed == 1
      assert ck_context.denied == 1
      assert ck_finding.allowed == 1
      assert ck_finding.denied == 0
    end

    test "recent/1 returns newest first, capped to limit" do
      for n <- 1..5 do
        :ok = McpAuditLog.record(:allowed, %{tool_name: "ck_context_#{n}", resource: "mcp"})
        Process.sleep(1100)
      end

      [first | _] = McpAuditLog.global_recent(limit: 3)
      assert String.ends_with?(first.tool_name, "_5")
      assert length(McpAuditLog.global_recent(limit: 3)) == 3
    end
  end

  describe "tenant isolation for scoped functions" do
    test "counts_by_tool/1 only returns data for specified workspace" do
      ws_a = workspace_fixture()
      ws_b = workspace_fixture()

      McpAuditLog.record(:allowed, %{workspace_id: ws_a.id, tool_name: "tool_x"})
      McpAuditLog.record(:denied, %{workspace_id: ws_b.id, tool_name: "tool_y"})

      counts_a = McpAuditLog.counts_by_tool(ws_a.id)
      assert length(counts_a) == 1
      assert hd(counts_a).tool_name == "tool_x"
      assert hd(counts_a).allowed == 1
      assert hd(counts_a).denied == 0
    end

    test "summary/1 only counts events for specified workspace" do
      ws_a = workspace_fixture()
      ws_b = workspace_fixture()

      McpAuditLog.record(:allowed, %{workspace_id: ws_a.id, tool_name: "t1"})
      McpAuditLog.record(:allowed, %{workspace_id: ws_a.id, tool_name: "t2"})
      McpAuditLog.record(:denied, %{workspace_id: ws_b.id, tool_name: "t3"})

      summary_a = McpAuditLog.summary(ws_a.id)
      assert summary_a.total == 2
      assert summary_a.allowed == 2
      assert summary_a.denied == 0
    end

    test "recent/2 only returns events for specified workspace" do
      ws_a = workspace_fixture()
      ws_b = workspace_fixture()

      McpAuditLog.record(:allowed, %{workspace_id: ws_a.id, tool_name: "t1"})
      McpAuditLog.record(:allowed, %{workspace_id: ws_b.id, tool_name: "t2"})

      recent_a = McpAuditLog.recent(ws_a.id, limit: 10)
      assert length(recent_a) == 1
      assert hd(recent_a).tool_name == "t1"
    end
  end
end
