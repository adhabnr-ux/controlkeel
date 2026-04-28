defmodule ControlKeel.CrossRuntimeContinuityTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Budget
  alias ControlKeel.Memory

  describe "ck_memory_search source_type/source_id filters" do
    test "finds finding shadow records by source_type filter" do
      session = session_fixture()

      # Create a finding — this creates both the finding record and a shadow memory record
      __finding = finding_fixture(%{session: session, title: "Cross-runtime checkpoint"})

      # Search with source_type filter should find the shadow record
      result =
        Memory.search("cross-runtime checkpoint",
          session_id: session.id,
          workspace_id: session.workspace_id,
          source_type: "finding"
        )

      assert result.total_count >= 1
      assert Enum.any?(result.entries, &(&1.source_type == "finding"))
    end

    test "finds finding shadow records by source_id filter" do
      session = session_fixture()

      finding = finding_fixture(%{session: session, title: "Unique finding for source_id test"})

      result =
        Memory.search("unique finding",
          session_id: session.id,
          workspace_id: session.workspace_id,
          source_id: to_string(finding.id)
        )

      assert result.total_count >= 1

      assert Enum.any?(result.entries, fn entry ->
               entry.source_id == to_string(finding.id)
             end)
    end

    test "combining source_type and source_id narrows to a single finding" do
      session = session_fixture()

      _other = finding_fixture(%{session: session, title: "Other finding"})
      target = finding_fixture(%{session: session, title: "Target finding for combined filter"})

      result =
        Memory.search("finding",
          session_id: session.id,
          workspace_id: session.workspace_id,
          source_type: "finding",
          source_id: to_string(target.id)
        )

      assert Enum.any?(result.entries, fn entry ->
               entry.source_id == to_string(target.id) and entry.source_type == "finding"
             end)
    end

    test "source_type filter excludes non-matching records" do
      session = session_fixture()

      # Create a finding (shadow record with source_type "finding")
      _finding = finding_fixture(%{session: session, title: "Security issue"})

      # Create a regular memory record with source_type "test"
      _memory =
        memory_record_fixture(%{
          session: session,
          title: "Security issue",
          summary: "Regular memory about security"
        })

      # Search with source_type "finding" should NOT find the regular memory record
      result =
        Memory.search("security",
          session_id: session.id,
          workspace_id: session.workspace_id,
          source_type: "finding"
        )

      assert Enum.all?(result.entries, &(&1.source_type == "finding"))
    end
  end

  describe "ck_budget status mode" do
    test "returns current budget state without requiring cost params" do
      session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 600, spent_cents: 200})

      assert {:ok, status} = Budget.status(%{"session_id" => session.id})

      assert status["session_budget_cents"] == 1_000
      assert status["spent_cents"] == 200
      assert status["remaining_session_cents"] == 800
      assert status["daily_budget_cents"] == 600
      assert status["decision"] == "allow"
    end

    test "returns warn decision when near the session cap" do
      session =
        session_fixture(%{budget_cents: 1_000, daily_budget_cents: 5_000, spent_cents: 850})

      assert {:ok, status} = Budget.status(%{"session_id" => session.id})

      assert status["decision"] == "warn"
      assert status["remaining_session_cents"] == 150
    end

    test "returns block decision when over the session cap" do
      session =
        session_fixture(%{budget_cents: 1_000, daily_budget_cents: 5_000, spent_cents: 1_200})

      assert {:ok, status} = Budget.status(%{"session_id" => session.id})

      assert status["decision"] == "block"
    end

    test "rejects missing session_id" do
      assert {:error, {:invalid_arguments, _}} = Budget.status(%{})
    end

    test "rejects unknown session" do
      assert {:error, {:invalid_arguments, _}} = Budget.status(%{"session_id" => 999_999})
    end
  end
end
