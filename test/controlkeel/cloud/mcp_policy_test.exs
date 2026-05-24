defmodule ControlKeel.Cloud.McpPolicyTest do
  use ControlKeel.DataCase, async: false

  import ControlKeel.MissionFixtures
  import ControlKeel.PlatformFixtures

  alias ControlKeel.Cloud.McpAuditLog
  alias ControlKeel.Cloud.McpPolicy
  alias ControlKeel.Cloud.McpToolCall
  alias ControlKeel.ProtocolInterop
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :cloud_mcp_policy)
    Application.delete_env(:controlkeel, :cloud_mcp_policy)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :cloud_mcp_policy, previous)
      else
        Application.delete_env(:controlkeel, :cloud_mcp_policy)
      end
    end)

    :ok
  end

  describe "check/3 with no policy configured" do
    test "returns :ok regardless of tool" do
      assert :ok = McpPolicy.check(%{}, "ck_context", "mcp")
      assert :ok = McpPolicy.check(%{}, "ck_delegate", "mcp")
    end
  end

  describe "check/3 deny-list" do
    setup do
      Application.put_env(:controlkeel, :cloud_mcp_policy, %{
        deny: ["ck_delegate", "ck_execute_code"]
      })

      :ok
    end

    test "rejects a denied tool" do
      assert {:error, {:policy, :tool_denied}} =
               McpPolicy.check(%{}, "ck_delegate", "mcp")
    end

    test "allows non-denied tools" do
      assert :ok = McpPolicy.check(%{}, "ck_context", "mcp")
    end
  end

  describe "check/3 rate limit" do
    setup do
      workspace = workspace_fixture()
      %{service_account: account} = service_account_fixture(%{workspace_id: workspace.id})

      Application.put_env(:controlkeel, :cloud_mcp_policy, %{
        rate_limits: [%{tool: "ck_context", per_minute: 2}]
      })

      auth = %{service_account: account, scopes: ["mcp:access", "context:read"]}
      {:ok, auth: auth, workspace: workspace}
    end

    test "allows until limit reached", %{auth: auth, workspace: workspace} do
      assert :ok = McpPolicy.check(auth, "ck_context", "mcp")

      # Pre-seed two allowed calls to push the workspace to the limit.
      seed_allowed(workspace.id, "ck_context", 2)

      assert {:error, {:policy, :rate_limit_exceeded}} =
               McpPolicy.check(auth, "ck_context", "mcp")
    end

    test "denied calls do not count toward the limit", %{auth: auth, workspace: workspace} do
      seed_denied(workspace.id, "ck_context", 5)
      assert :ok = McpPolicy.check(auth, "ck_context", "mcp")
    end

    test "calls older than the window do not count", %{auth: auth, workspace: workspace} do
      seed_allowed(workspace.id, "ck_context", 2, age_seconds: 120)
      assert :ok = McpPolicy.check(auth, "ck_context", "mcp")
    end

    test "wildcard rule applies when no exact rule matches" do
      workspace = workspace_fixture()
      %{service_account: account} = service_account_fixture(%{workspace_id: workspace.id})

      Application.put_env(:controlkeel, :cloud_mcp_policy, %{
        rate_limits: [%{tool: "*", per_minute: 1}]
      })

      auth = %{service_account: account, scopes: []}

      seed_allowed(workspace.id, "ck_route", 1)

      assert {:error, {:policy, :rate_limit_exceeded}} =
               McpPolicy.check(auth, "ck_route", "mcp")
    end
  end

  describe "integration via ProtocolInterop" do
    test "policy denial short-circuits scope checks and records audit reason" do
      workspace = workspace_fixture()
      %{service_account: account} = service_account_fixture(%{workspace_id: workspace.id})

      Application.put_env(:controlkeel, :cloud_mcp_policy, %{deny: ["ck_delegate"]})

      auth = %{
        service_account: account,
        # Scopes intentionally absent — proves policy fires before scope check.
        scopes: [],
        resource_access_id: "mcp"
      }

      assert {:error, {:policy, :tool_denied}} =
               ProtocolInterop.authorize_hosted_tool_call(auth, "ck_delegate", %{}, "mcp")

      [row] = Repo.all(McpToolCall)
      assert row.outcome == "denied"
      assert row.denial_reason == "policy:tool_denied"

      assert McpAuditLog.summary().denied == 1
    end
  end

  defp seed_allowed(workspace_id, tool_name, count, opts \\ []) do
    age = Keyword.get(opts, :age_seconds, 0)
    ts = DateTime.utc_now() |> DateTime.add(-age, :second) |> DateTime.truncate(:second)

    for _ <- 1..count do
      Repo.insert!(%McpToolCall{
        workspace_id: workspace_id,
        resource: "mcp",
        tool_name: tool_name,
        outcome: "allowed",
        requested_at: ts
      })
    end
  end

  defp seed_denied(workspace_id, tool_name, count) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)

    for _ <- 1..count do
      Repo.insert!(%McpToolCall{
        workspace_id: workspace_id,
        resource: "mcp",
        tool_name: tool_name,
        outcome: "denied",
        denial_reason: "test",
        requested_at: ts
      })
    end
  end
end
