defmodule ControlKeel.Platform.NhiAuditEventTest do
  use ControlKeel.DataCase

  alias ControlKeel.Platform
  alias ControlKeel.Platform.NhiAuditEvent

  import ControlKeel.MissionFixtures

  setup do
    workspace = workspace_fixture()
    {:ok, workspace: workspace}
  end

  describe "provision_agent_identity/3" do
    test "creates service account and provisioned audit event", %{workspace: ws} do
      assert {:ok, %{service_account: account, token: token}} =
               Platform.provision_agent_identity(
                 ws.id,
                 %{
                   name: "ci-bot",
                   scopes: ["mcp:access", "validate:run"]
                 },
                 actor: "admin@example.com"
               )

      assert account.status == "active"
      assert is_binary(token)

      events = Platform.list_nhi_audit_events(account.id)
      assert length(events) == 1
      [event] = events
      assert event.event_type == "provisioned"
      assert event.actor == "admin@example.com"
    end
  end

  describe "revoke_agent_identity/2" do
    test "revokes account and records deprovisioned event", %{workspace: ws} do
      {:ok, %{service_account: account}} =
        Platform.provision_agent_identity(ws.id, %{name: "bot", scopes: ["mcp:access"]})

      assert {:ok, revoked} = Platform.revoke_agent_identity(account.id, actor: "operator")
      assert revoked.status == "revoked"

      events = Platform.list_nhi_audit_events(account.id)
      types = Enum.map(events, & &1.event_type)
      assert "provisioned" in types
      assert "deprovisioned" in types
    end

    test "returns not_found for unknown id" do
      assert {:error, :not_found} = Platform.revoke_agent_identity(999_999)
    end
  end

  describe "rotate_agent_identity_token/2" do
    test "rotates token and records token_rotated event", %{workspace: ws} do
      {:ok, %{service_account: account, token: original_token}} =
        Platform.provision_agent_identity(ws.id, %{name: "bot", scopes: ["mcp:access"]})

      assert {:ok, %{service_account: _updated, token: new_token}} =
               Platform.rotate_agent_identity_token(account.id)

      refute new_token == original_token

      events = Platform.list_nhi_audit_events(account.id)
      assert Enum.any?(events, &(&1.event_type == "token_rotated"))
    end
  end

  describe "nhi_lifecycle_summary/1" do
    test "returns summary with counts", %{workspace: ws} do
      {:ok, %{service_account: a1}} =
        Platform.provision_agent_identity(ws.id, %{name: "bot-1", scopes: ["mcp:access"]})

      {:ok, %{service_account: a2}} =
        Platform.provision_agent_identity(ws.id, %{name: "bot-2", scopes: ["mcp:access"]})

      Platform.revoke_agent_identity(a2.id)

      summary = Platform.nhi_lifecycle_summary(ws.id)
      assert summary.total == 2
      assert summary.active == 1
      assert summary.revoked == 1
      assert length(summary.identities) == 2

      bot1 = Enum.find(summary.identities, &(&1.id == a1.id))
      assert bot1.last_event_type == "provisioned"
    end

    test "returns empty summary for workspace with no identities", %{workspace: ws} do
      summary = Platform.nhi_lifecycle_summary(ws.id)
      assert summary.total == 0
      assert summary.active == 0
      assert summary.identities == []
    end
  end

  describe "record_nhi_event/3" do
    test "records a custom event", %{workspace: ws} do
      {:ok, %{service_account: account}} =
        Platform.provision_agent_identity(ws.id, %{name: "bot", scopes: ["mcp:access"]})

      assert {:ok, event} =
               Platform.record_nhi_event(account.id, "last_used_updated",
                 metadata: %{"ip" => "10.0.0.1"}
               )

      assert event.event_type == "last_used_updated"
      assert NhiAuditEvent.decode_metadata(event)["ip"] == "10.0.0.1"
    end
  end
end
