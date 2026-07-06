defmodule ControlKeel.Learning.OutcomeTrackerTest do
  use ControlKeel.DataCase

  alias ControlKeel.Learning.OutcomeTracker
  import ControlKeel.MissionFixtures

  test "record persists a valid outcome" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    assert {:ok, result} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "claude",
               task_type: "deployment",
               workspace_id: workspace.workspace_id
             )

    assert result.outcome == :deploy_success
    assert result.reward == 1.0
  end

  test "record infers workspace from the session when omitted" do
    session = session_fixture()

    assert {:ok, result} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "claude",
               task_type: "deployment"
             )

    assert result.outcome == :deploy_success
  end

  test "record rejects unknown outcome" do
    session = session_fixture()

    assert {:error, {:unknown_outcome, :bogus}} =
             OutcomeTracker.record(session.id, :bogus)
  end

  test "valid_outcomes lists all supported outcomes" do
    outcomes = OutcomeTracker.valid_outcomes()
    assert :deploy_success in outcomes
    assert :deploy_failure in outcomes
    assert :test_pass in outcomes
    assert :budget_exceeded in outcomes
    assert :prompt_first_pass in outcomes
    assert :prompt_refined_once in outcomes
    assert :prompt_refined_repeatedly in outcomes
    assert :prompt_abandoned in outcomes
    assert length(outcomes) == 14
  end

  describe "record_prompt_outcome/3" do
    test "maps depth 1 + approved to prompt_first_pass" do
      session = session_fixture()

      assert {:ok, result} =
               OutcomeTracker.record_prompt_outcome(session.id, %{
                 depth: 1,
                 status: "approved",
                 review_id: 42
               })

      assert result.outcome == :prompt_first_pass
      assert result.reward > 0
    end

    test "maps depth 2 + approved to prompt_refined_once" do
      session = session_fixture()

      assert {:ok, result} =
               OutcomeTracker.record_prompt_outcome(session.id, %{
                 depth: 2,
                 status: "approved",
                 review_id: 43
               })

      assert result.outcome == :prompt_refined_once
    end

    test "maps depth 3+ + approved to prompt_refined_repeatedly with negative reward" do
      session = session_fixture()

      assert {:ok, result} =
               OutcomeTracker.record_prompt_outcome(session.id, %{
                 depth: 5,
                 status: "approved",
                 review_id: 44
               })

      assert result.outcome == :prompt_refined_repeatedly
      assert result.reward < 0
    end

    test "maps denied to prompt_abandoned regardless of depth" do
      session = session_fixture()

      assert {:ok, result} =
               OutcomeTracker.record_prompt_outcome(session.id, %{
                 depth: 1,
                 status: "denied",
                 review_id: 45
               })

      assert result.outcome == :prompt_abandoned
    end

    test "skips on unknown status without error" do
      session = session_fixture()

      assert {:ok, :skipped} =
               OutcomeTracker.record_prompt_outcome(session.id, %{
                 depth: 1,
                 status: "pending",
                 review_id: 46
               })
    end
  end

  test "rewards have expected sign and range" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    assert {:ok, pos} =
             OutcomeTracker.record(session.id, :deploy_success,
               agent_id: "a",
               workspace_id: workspace.workspace_id
             )

    assert pos.reward > 0

    assert {:ok, neg} =
             OutcomeTracker.record(session.id, :deploy_failure,
               agent_id: "a",
               workspace_id: workspace.workspace_id
             )

    assert neg.reward < 0
  end

  test "get_agent_score returns zero for unknown agent" do
    assert {:ok, score} = OutcomeTracker.get_agent_score("nonexistent_agent_xyz")
    assert score.score == 0.0
    assert score.outcome_count == 0
  end

  test "get_leaderboard returns list" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    OutcomeTracker.record(session.id, :deploy_success,
      agent_id: "lb_good",
      workspace_id: workspace.workspace_id
    )

    OutcomeTracker.record(session.id, :deploy_failure,
      agent_id: "lb_bad",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, leaderboard} =
             OutcomeTracker.get_leaderboard(workspace_id: workspace.workspace_id)

    assert is_list(leaderboard)
  end

  test "get_session_outcomes returns outcomes for a session" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    {:ok, _} =
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "so_1",
        workspace_id: workspace.workspace_id
      )

    {:ok, _} =
      OutcomeTracker.record(session.id, :test_pass,
        agent_id: "so_2",
        workspace_id: workspace.workspace_id
      )

    assert {:ok, outcomes} = OutcomeTracker.get_session_outcomes(session.id)
    assert length(outcomes) == 2

    outcome_names = Enum.map(outcomes, &Map.get(&1, "outcome"))
    assert "deploy_success" in outcome_names
    assert "test_pass" in outcome_names
  end

  test "get_session_outcomes returns empty for unknown session" do
    assert {:ok, outcomes} = OutcomeTracker.get_session_outcomes(999_999_999)
    assert outcomes == []
  end

  test "within_window excludes entries with invalid timestamps" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    {:ok, _} =
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "window_test",
        workspace_id: workspace.workspace_id
      )

    {:ok, _} =
      ControlKeel.Memory.record(%{
        workspace_id: workspace.workspace_id,
        session_id: session.id,
        record_type: "decision",
        title: "Outcome: Corrupted entry for window_test",
        summary: "Agent window_test outcome with bad timestamp",
        body: "outcome agent window_test",
        tags: ["outcome", "deploy_success", "window_test"],
        source_type: "outcome_tracker",
        source_id: "outcome:#{session.id}:bad_ts",
        metadata: %{
          "outcome" => "deploy_success",
          "reward" => 1.0,
          "label" => "Deploy Succeeded",
          "agent_id" => "window_test",
          "session_id" => session.id,
          "recorded_at" => "not-a-valid-timestamp"
        }
      })

    assert {:ok, score} = OutcomeTracker.get_agent_score("window_test")
    assert score.outcome_count == 1
  end

  test "compute_router_weights returns map" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    OutcomeTracker.record(session.id, :deploy_success,
      agent_id: "rw_1",
      workspace_id: workspace.workspace_id
    )

    OutcomeTracker.record(session.id, :test_pass,
      agent_id: "rw_2",
      workspace_id: workspace.workspace_id
    )

    assert {:ok, weights} = OutcomeTracker.compute_router_weights()
    assert is_map(weights)
  end

  test "compute_router_weights gates contributors by min_samples" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    for _ <- 1..2 do
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "few_samples",
        workspace_id: workspace.workspace_id
      )
    end

    for _ <- 1..5 do
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "many_samples",
        workspace_id: workspace.workspace_id
      )
    end

    assert {:ok, gated} = OutcomeTracker.compute_router_weights(min_samples: 5)
    assert Map.has_key?(gated, "many_samples")
    refute Map.has_key?(gated, "few_samples")

    assert {:ok, ungated} = OutcomeTracker.compute_router_weights(min_samples: 0)
    assert Map.has_key?(ungated, "few_samples")
  end

  test "compute_router_weights preserves negative outcomes as penalties" do
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    for _ <- 1..5 do
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "good_agent",
        workspace_id: workspace.workspace_id
      )

      OutcomeTracker.record(session.id, :deploy_failure,
        agent_id: "bad_agent",
        workspace_id: workspace.workspace_id
      )
    end

    assert {:ok, weights} = OutcomeTracker.compute_router_weights(min_samples: 5)
    assert weights["good_agent"] > 0
    assert weights["bad_agent"] < 0
  end

  test "recorded outcomes close the learning loop into router ranking" do
    # Baseline: no outcomes recorded -> router uses the pure static heuristic.
    assert {:ok, baseline} =
             ControlKeel.Agent.Router.route("Automate webhook connector flows",
               risk_tier: "low",
               allowed_agents: ["n8n", "make"]
             )

    assert baseline.policy_source == "heuristic"

    # Record enough outcomes (>= the router's min-sample floor) to qualify an agent.
    session = session_fixture()
    workspace = ControlKeel.Mission.get_session!(session.id)

    for _ <- 1..6 do
      OutcomeTracker.record(session.id, :deploy_success,
        agent_id: "n8n",
        workspace_id: workspace.workspace_id
      )
    end

    assert {:ok, learned} =
             ControlKeel.Agent.Router.route("Automate webhook connector flows",
               risk_tier: "low",
               allowed_agents: ["n8n", "make"]
             )

    # The learned signal now reaches routing: policy provenance reflects it.
    assert learned.policy_source == "heuristic+learned"
  end
end
