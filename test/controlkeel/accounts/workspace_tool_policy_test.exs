defmodule ControlKeel.Accounts.WorkspaceToolPolicyTest do
  use ControlKeel.DataCase

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy

  import ControlKeel.MissionFixtures

  setup do
    workspace = workspace_fixture()
    {:ok, workspace: workspace}
  end

  describe "get_workspace_tool_policy/1" do
    test "returns a default inherit policy when none configured", %{workspace: ws} do
      policy = Accounts.get_workspace_tool_policy(ws.id)
      assert policy.mode == "inherit"
      assert WorkspaceToolPolicy.decode_tools(policy) == []
    end
  end

  describe "set_workspace_tool_policy/3" do
    test "creates a new allowlist policy", %{workspace: ws} do
      assert {:ok, policy} = Accounts.set_workspace_tool_policy(ws.id, "allowlist", ["ck_validate", "ck_finding"])
      assert policy.mode == "allowlist"
      assert WorkspaceToolPolicy.decode_tools(policy) == ["ck_validate", "ck_finding"]
    end

    test "upserts on second call", %{workspace: ws} do
      {:ok, _} = Accounts.set_workspace_tool_policy(ws.id, "allowlist", ["ck_validate"])
      {:ok, updated} = Accounts.set_workspace_tool_policy(ws.id, "denylist", ["ck_delegate"])
      assert updated.mode == "denylist"
      assert WorkspaceToolPolicy.decode_tools(updated) == ["ck_delegate"]
    end

    test "rejects invalid mode", %{workspace: ws} do
      assert {:error, changeset} = Accounts.set_workspace_tool_policy(ws.id, "unknown", [])
      assert %{mode: [_]} = errors_on(changeset)
    end
  end

  describe "check_workspace_tool_policy/2" do
    test "returns :ok for nil workspace_id" do
      assert :ok = Accounts.check_workspace_tool_policy(nil, "ck_validate")
    end

    test "returns :ok for inherit mode (default)", %{workspace: ws} do
      assert :ok = Accounts.check_workspace_tool_policy(ws.id, "ck_delegate")
    end

    test "allowlist: allows tools in the list", %{workspace: ws} do
      Accounts.set_workspace_tool_policy(ws.id, "allowlist", ["ck_validate", "ck_finding"])
      assert :ok = Accounts.check_workspace_tool_policy(ws.id, "ck_validate")
    end

    test "allowlist: blocks tools not in the list", %{workspace: ws} do
      Accounts.set_workspace_tool_policy(ws.id, "allowlist", ["ck_validate"])
      assert {:error, {:policy, :tool_not_in_workspace_allowlist}} =
               Accounts.check_workspace_tool_policy(ws.id, "ck_delegate")
    end

    test "denylist: blocks tools in the list", %{workspace: ws} do
      Accounts.set_workspace_tool_policy(ws.id, "denylist", ["ck_delegate"])
      assert {:error, {:policy, :tool_in_workspace_denylist}} =
               Accounts.check_workspace_tool_policy(ws.id, "ck_delegate")
    end

    test "denylist: allows tools not in the list", %{workspace: ws} do
      Accounts.set_workspace_tool_policy(ws.id, "denylist", ["ck_delegate"])
      assert :ok = Accounts.check_workspace_tool_policy(ws.id, "ck_validate")
    end
  end
end
