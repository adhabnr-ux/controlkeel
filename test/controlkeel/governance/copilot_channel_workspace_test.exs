defmodule ControlKeel.Governance.CopilotChannelWorkspaceTest do
  use ControlKeel.DataCase

  alias ControlKeel.Governance.CopilotChannel

  describe "subscribe_workspace/1" do
    test "subscribes the current process to workspace events" do
      CopilotChannel.subscribe_workspace(42)

      CopilotChannel.broadcast_workspace(42, "sync.completed", %{"pushed" => 5})

      assert_received {:workspace_event, "sync.completed", %{"pushed" => 5}}
    end

    test "does not receive events from other workspaces" do
      CopilotChannel.subscribe_workspace(42)

      CopilotChannel.broadcast_workspace(99, "sync.completed", %{"pushed" => 1})

      refute_received {:workspace_event, _, _}
    end
  end

  describe "broadcast_workspace/3" do
    test "broadcasts to all subscribers on the same workspace" do
      CopilotChannel.subscribe_workspace(42)

      CopilotChannel.broadcast_workspace(42, "finding.raised", %{"rule_id" => "CK-TEST-001"})

      assert_received {:workspace_event, "finding.raised", %{"rule_id" => "CK-TEST-001"}}
    end

    test "uses default empty payload" do
      CopilotChannel.subscribe_workspace(42)
      CopilotChannel.broadcast_workspace(42, "ping")

      assert_received {:workspace_event, "ping", %{}}
    end
  end

  describe "workspace_topic/1" do
    test "returns the expected topic format" do
      assert CopilotChannel.workspace_topic(42) == "ck_workspace:42"
    end
  end
end
