defmodule ControlKeel.Cloud.SyncHardeningTest do
  @moduledoc """
  Round-trip tests that exercise the load-bearing semantics of cloud sync.
  Each test names the finding it closes.
  """

  use ControlKeel.DataCase

  alias ControlKeel.Cloud.Sync
  alias ControlKeel.Governance.WorkspaceAgent, as: WorkspaceAgentManager
  alias ControlKeel.Mission

  defp workspace!(seed) do
    {:ok, ws} =
      Mission.create_workspace(%{
        name: "Hardening-#{seed}",
        slug: "hardening-#{seed}-#{:rand.uniform(99_999)}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    ws
  end

  defp session!(ws, title) do
    {:ok, s} =
      Mission.create_session(%{
        title: title,
        objective: "hardening",
        risk_tier: "low",
        budget_cents: 10_000,
        daily_budget_cents: 5_000,
        workspace_id: ws.id
      })

    s
  end

  describe "serialize_record/1 (closes CK-CLOUD-SYNC-001)" do
    test "redacts credential-shaped substrings from memory_record body before egress" do
      ws = workspace!("redact")
      s = session!(ws, "S")

      {:ok, mem} =
        %ControlKeel.Memory.Record{}
        |> ControlKeel.Memory.Record.changeset(%{
          workspace_id: ws.id,
          session_id: s.id,
          record_type: "decision",
          title: "leaked content",
          summary: "S",
          body:
            "User pasted: Authorization: Bearer abc123def456 and OPENAI_API_KEY=sk-secretkey0123456789",
          tags: [],
          source_type: "system",
          metadata: %{}
        })
        |> Repo.insert()

      envelope = Sync.serialize_record({"memory_record", mem})
      body = envelope["payload"]["body"]

      refute body =~ "abc123def456"
      refute body =~ "sk-secretkey0123456789"
      assert body =~ "[REDACTED]"
    end

    test "drops fields not in the schema's sync_fields/0 allowlist" do
      ws = workspace!("allowlist")
      s = session!(ws, "S")

      {:ok, f} =
        Mission.create_finding(%{
          session_id: s.id,
          title: "f",
          severity: "low",
          category: "code_quality",
          rule_id: "CK-ALLOW-001",
          plain_message: "ok",
          status: "open",
          metadata: %{}
        })

      envelope = Sync.serialize_record({"finding", f})
      payload = envelope["payload"]

      # Allowlisted
      assert Map.has_key?(payload, "external_id")
      assert Map.has_key?(payload, "rule_id")

      # NOT in the allowlist: Ecto association preloads + struct __meta__
      refute Map.has_key?(payload, "session")
      refute Map.has_key?(payload, "__meta__")
      refute Map.has_key?(payload, "__struct__")
    end

    test "stamps envelopes with sync_protocol_version and redaction_policy_version" do
      ws = workspace!("version")
      s = session!(ws, "S")

      {:ok, f} =
        Mission.create_finding(%{
          session_id: s.id,
          title: "f",
          severity: "low",
          category: "code_quality",
          rule_id: "CK-VER-001",
          plain_message: "ok",
          status: "open",
          metadata: %{}
        })

      envelope = Sync.serialize_record({"finding", f})

      assert envelope["sync_protocol_version"] == Sync.protocol_version()
      assert is_binary(envelope["redaction_policy_version"])
    end
  end

  describe "do_upsert append-only path (closes CK-CLOUD-SYNC-003)" do
    test "cloud-side status change propagates when incoming updated_at is newer" do
      ws = workspace!("status")
      s = session!(ws, "S")

      {:ok, f} =
        Mission.create_finding(%{
          session_id: s.id,
          title: "f",
          severity: "high",
          category: "security",
          rule_id: "CK-STATUS-001",
          plain_message: "ok",
          status: "open",
          metadata: %{}
        })

      newer = DateTime.add(f.updated_at, 120, :second) |> DateTime.to_iso8601()

      envelope = %{
        "external_id" => f.external_id,
        "kind" => "finding",
        "payload" => %{
          "title" => f.title,
          "severity" => f.severity,
          "category" => f.category,
          "rule_id" => f.rule_id,
          "plain_message" => f.plain_message,
          "status" => "blocked",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id,
          "updated_at" => newer
        }
      }

      assert {:ok, %{updated: 1}} = Sync.upsert_batch([envelope])

      refreshed = Repo.get!(ControlKeel.Mission.Finding, f.id)
      assert refreshed.status == "blocked"
    end

    test "older incoming updated_at is a no-op" do
      ws = workspace!("older")
      s = session!(ws, "S")

      {:ok, f} =
        Mission.create_finding(%{
          session_id: s.id,
          title: "f",
          severity: "high",
          category: "security",
          rule_id: "CK-STATUS-002",
          plain_message: "ok",
          status: "open",
          metadata: %{}
        })

      older = DateTime.add(f.updated_at, -120, :second) |> DateTime.to_iso8601()

      envelope = %{
        "external_id" => f.external_id,
        "kind" => "finding",
        "payload" => %{
          "title" => f.title,
          "severity" => f.severity,
          "category" => f.category,
          "rule_id" => f.rule_id,
          "plain_message" => f.plain_message,
          "status" => "blocked",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id,
          "updated_at" => older
        }
      }

      assert {:ok, %{no_change: 1, updated: 0}} = Sync.upsert_batch([envelope])

      refreshed = Repo.get!(ControlKeel.Mission.Finding, f.id)
      assert refreshed.status == "open"
    end
  end

  describe "update_editable (closes CK-CLOUD-SYNC-004)" do
    test "WorkspaceAgent lock_version actually bumps in the DB after a sync update" do
      ws = workspace!("agent")

      {:ok, agent} =
        WorkspaceAgentManager.register(%{
          workspace_id: ws.id,
          name: "test",
          role: "specialized",
          agent_type: "claude-code",
          budget_cents: 1_000
        })

      assert agent.lock_version == 1

      envelope = %{
        "external_id" => agent.external_id,
        "kind" => "workspace_agent",
        "payload" => %{
          "workspace_id" => ws.id,
          "name" => "renamed-from-cloud",
          "role" => agent.role,
          "agent_type" => agent.agent_type,
          "status" => "active",
          "budget_cents" => 2_000,
          "lock_version" => 5
        }
      }

      assert {:ok, %{updated: 1}} = Sync.upsert_batch([envelope])

      refreshed = Repo.get!(ControlKeel.Mission.WorkspaceAgent, agent.id)
      assert refreshed.lock_version == 2
      assert refreshed.name == "renamed-from-cloud"
    end

    test "lock_version stale_or_equal is a no-op" do
      ws = workspace!("agent-stale")

      {:ok, agent} =
        WorkspaceAgentManager.register(%{
          workspace_id: ws.id,
          name: "test",
          role: "specialized",
          agent_type: "claude-code"
        })

      envelope = %{
        "external_id" => agent.external_id,
        "kind" => "workspace_agent",
        "payload" => %{
          "workspace_id" => ws.id,
          "name" => "ignored",
          "role" => agent.role,
          "agent_type" => agent.agent_type,
          "status" => "active",
          "lock_version" => 1
        }
      }

      assert {:ok, %{no_change: 1}} = Sync.upsert_batch([envelope])

      refreshed = Repo.get!(ControlKeel.Mission.WorkspaceAgent, agent.id)
      assert refreshed.name == "test"
      assert refreshed.lock_version == 1
    end
  end

  describe "protocol versioning (closes CK-CLOUD-SYNC-010)" do
    test "envelope with mismatched sync_protocol_version is upserted but logged" do
      ws = workspace!("proto")
      s = session!(ws, "S")

      envelope = %{
        "external_id" => "f_PROTO#{:rand.uniform(99_999)}",
        "kind" => "finding",
        "sync_protocol_version" => 999,
        "payload" => %{
          "title" => "f",
          "severity" => "low",
          "category" => "code_quality",
          "rule_id" => "CK-PROTO-001",
          "plain_message" => "ok",
          "status" => "open",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id
        }
      }

      import ExUnit.CaptureLog
      log = capture_log(fn -> assert {:ok, _} = Sync.upsert_batch([envelope]) end)
      assert log =~ "protocol version"
    end
  end
end
