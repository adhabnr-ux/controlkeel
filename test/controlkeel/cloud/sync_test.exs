defmodule ControlKeel.Cloud.SyncTest do
  use ControlKeel.DataCase

  alias ControlKeel.Cloud.Sync
  alias ControlKeel.Mission

  defp workspace!(seed) do
    {:ok, ws} =
      Mission.create_workspace(%{
        name: "Sync-#{seed}",
        slug: "sync-#{seed}-#{:rand.uniform(99_999)}",
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })

    ws
  end

  defp session!(ws, title \\ "S") do
    {:ok, s} =
      Mission.create_session(%{
        title: title,
        objective: "sync test",
        risk_tier: "low",
        budget_cents: 10_000,
        daily_budget_cents: 5_000,
        workspace_id: ws.id
      })

    s
  end

  defp finding!(session, rule_id, path \\ "lib/foo.ex") do
    {:ok, f} =
      Mission.create_finding(%{
        session_id: session.id,
        title: "test finding",
        severity: "medium",
        category: "code_quality",
        rule_id: rule_id,
        plain_message: "test",
        status: "open",
        metadata: %{"path" => path}
      })

    f
  end

  describe "collect_unsynced/2" do
    test "returns unsynced findings for a workspace" do
      ws = workspace!("collect")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-001")

      result = Sync.collect_unsynced(ws.id)
      assert result.total >= 1

      {kind, record} = Enum.find(result.records, fn {k, _} -> k == "finding" end)
      assert kind == "finding"
      assert record.id == f.id
      assert record.external_id != nil
      assert String.starts_with?(record.external_id, "f_")
    end

    test "excludes already-synced records" do
      ws = workspace!("synced")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-002")

      # Mark as synced
      f.__struct__.changeset(f, %{synced_at: DateTime.utc_now()})
      |> Repo.update!()

      result = Sync.collect_unsynced(ws.id)
      finding_records = Enum.filter(result.records, fn {k, _} -> k == "finding" end)
      assert Enum.find(finding_records, fn {_, r} -> r.id == f.id end) == nil
    end

    test "returns empty for workspace with no sessions" do
      ws = workspace!("empty")
      result = Sync.collect_unsynced(ws.id)
      assert result.total == 0
    end
  end

  describe "serialize_record/1" do
    test "produces a valid sync envelope" do
      ws = workspace!("serialize")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-003")

      envelope = Sync.serialize_record({"finding", f})

      assert envelope["external_id"] == f.external_id
      assert envelope["kind"] == "finding"
      assert is_map(envelope["payload"])
      assert envelope["idempotency_key"] != nil
    end
  end

  describe "upsert_batch/1" do
    test "inserts new records from cloud" do
      ws = workspace!("upsert")
      s = session!(ws, "S1")

      envelope = %{
        "external_id" => "f_TESTINSERT#{:rand.uniform(99_999)}",
        "kind" => "finding",
        "payload" => %{
          "title" => "from cloud",
          "severity" => "high",
          "category" => "security",
          "rule_id" => "CK-CLOUD-001",
          "plain_message" => "cloud finding",
          "status" => "open",
          "auto_resolved" => false,
          "metadata" => %{},
          "session_id" => s.id
        }
      }

      result = Sync.upsert_batch([envelope])
      assert result.inserted == 1
      assert result.skipped == 0

      # Second upsert: record exists, synced_at still nil, so it updates
      result2 = Sync.upsert_batch([envelope])
      assert result2.updated == 1
    end

    test "rejects unknown kind" do
      envelope = %{
        "external_id" => "unknown_123",
        "kind" => "nonexistent",
        "payload" => %{}
      }

      result = Sync.upsert_batch([envelope])
      assert result.skipped == 1
    end
  end

  describe "mark_synced/1" do
    test "sets synced_at on records" do
      ws = workspace!("mark")
      s = session!(ws, "S1")
      f = finding!(s, "CK-SYNC-004")

      assert f.synced_at == nil

      Sync.mark_synced([{"finding", f}])

      refreshed = Repo.get!(ControlKeel.Mission.Finding, f.id)
      assert refreshed.synced_at != nil
    end
  end
end
