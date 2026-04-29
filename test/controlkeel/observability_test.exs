defmodule ControlKeel.ObservabilityTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Invocation, SessionEvent}
  alias ControlKeel.Observability
  alias ControlKeel.Repo

  test "session_run/1 composes health, costs, gates, memory, proofs, timeline, and calls" do
    session = session_fixture(%{budget_cents: 1_000, daily_budget_cents: 2_000, spent_cents: 850})
    task = task_fixture(%{session: session, status: "in_progress"})

    _finding =
      finding_fixture(%{
        session: session,
        title: "Critical gate",
        severity: "critical",
        status: "blocked",
        rule_id: "security.critical_gate"
      })

    assert {:ok, _review} =
             Mission.submit_review(%{
               "session_id" => session.id,
               "task_id" => task.id,
               "review_type" => "plan",
               "title" => "Pending review",
               "submission_body" => "Need approval"
             })

    assert {:ok, _event} =
             %SessionEvent{}
             |> SessionEvent.changeset(%{
               session_id: session.id,
               task_id: task.id,
               event_type: "tool_call",
               actor: "agent",
               summary: "Ran validation",
               payload: %{},
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               task_id: task.id,
               source: "opencode",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               estimated_cost_cents: 12,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _proof} = Mission.generate_proof_bundle(task.id)

    assert {:ok, run} = Observability.session_run(session.id)

    assert run.session.id == session.id
    assert run.health.status == "red"
    assert run.findings.active == 1
    assert run.findings.critical == 1
    assert run.findings.blocked == 1
    assert run.gates.pending_reviews == 1
    assert run.timeline.count >= 1
    assert run.proofs.count == 1
    assert run.hosts_models_tools.invocations == 1
    assert run.hosts_models_tools.estimated_cost_cents == 12
    assert run.budget["decision"] == "warn"
    assert Enum.any?(run.recommendations, &String.contains?(&1, "blocked or critical"))
  end

  test "problems/1 groups active findings by rule and category" do
    session = session_fixture()
    workspace = Repo.preload(session, :workspace).workspace
    other_session = session_fixture(%{workspace: workspace})

    finding_fixture(%{
      session: session,
      title: "SQL issue one",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.sql_injection"
    })

    finding_fixture(%{
      session: other_session,
      title: "SQL issue two",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.sql_injection"
    })

    finding_fixture(%{
      session: session,
      title: "Other issue",
      severity: "medium",
      status: "open",
      category: "review",
      rule_id: "review.required"
    })

    problems = Observability.problems(workspace_id: session.workspace_id)

    assert problems.count == 2
    assert problems.health == "red"

    sql_problem = Enum.find(problems.problems, &(&1.rule_id == "security.sql_injection"))
    assert sql_problem.count == 2
    assert sql_problem.affected_session_count == 2
    assert sql_problem.health == "red"
    assert sql_problem.severity == "critical"

    assert sql_problem.feedback_loop.eval_candidate_title ==
             "Regression eval for security.sql_injection"

    assert sql_problem.feedback_loop.evidence_kind == "finding_group"
    assert sql_problem.feedback_loop.human_gate_required == true
    assert sql_problem.feedback_loop.benchmark_hint == "security-regression"
    assert sql_problem.feedback_loop.suggested_action =~ "regression benchmark"
    assert Enum.any?(sql_problem.examples, &(&1.session_id == session.id))
  end

  test "session_run/1 returns not_found for unknown sessions" do
    assert {:error, :not_found} = Observability.session_run(999_999)
  end
end
