defmodule ControlKeel.ObservabilityTest do
  use ControlKeel.DataCase

  import ControlKeel.MissionFixtures

  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Invocation, Session, SessionEvent}
  alias ControlKeel.Observability
  alias ControlKeel.Observability.Telemetry, as: ObservabilityTelemetry
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

  test "timeline/2 summarizes recent session events" do
    session = session_fixture()

    assert {:ok, _event} =
             %SessionEvent{}
             |> SessionEvent.changeset(%{
               session_id: session.id,
               event_type: "tool_call",
               actor: "agent",
               summary: "Ran timeline validation",
               body: "Detailed event body",
               payload: %{},
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, timeline} = Observability.timeline(session.id, limit: 10)

    assert timeline.session.id == session.id
    assert timeline.count >= 1
    assert timeline.limit == 10
    assert timeline.by_event_type["tool_call"] == 1
    assert timeline.by_actor["agent"] == 1
    assert Enum.any?(timeline.events, &(&1.summary == "Ran timeline validation"))
  end

  test "costs/1 summarizes invocation spend and groups by selected field" do
    session = session_fixture()
    workspace = Repo.preload(session, :workspace).workspace
    other_session = session_fixture(%{workspace: workspace})

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_000,
               cached_input_tokens: 200,
               output_tokens: 300,
               estimated_cost_cents: 14,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: other_session.id,
               source: "opencode",
               tool: "ck_budget",
               provider: "anthropic",
               model: "claude-sonnet",
               input_tokens: 500,
               cached_input_tokens: 0,
               output_tokens: 100,
               estimated_cost_cents: 6,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    costs = Observability.costs(workspace_id: session.workspace_id, by: "provider")

    assert costs.by == "provider"
    assert costs.totals.invocations == 2
    assert costs.totals.sessions == 2
    assert costs.totals.estimated_cost_cents == 20
    assert costs.totals.input_tokens == 1_500
    assert costs.totals.cached_input_tokens == 200
    assert costs.totals.output_tokens == 400
    assert Enum.map(costs.groups, & &1.name) == ["openai", "anthropic"]
    assert Enum.any?(costs.recommendations, &String.contains?(&1, "cost per successful task"))
  end

  test "comparison/1 compares invocation groups by selected field" do
    session = session_fixture()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 900,
               output_tokens: 300,
               estimated_cost_cents: 12,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "opencode",
               tool: "ck_review_submit",
               provider: "anthropic",
               model: "claude-sonnet",
               input_tokens: 300,
               output_tokens: 100,
               estimated_cost_cents: 4,
               decision: "warn",
               metadata: %{}
             })
             |> Repo.insert()

    comparison = Observability.comparison(workspace_id: session.workspace_id, by: "source")

    assert comparison.by == "source"
    assert comparison.totals.invocations == 2
    assert comparison.totals.estimated_cost_cents == 16
    assert Enum.map(comparison.groups, & &1.name) == ["codex-cli", "opencode"]

    codex = Enum.find(comparison.groups, &(&1.name == "codex-cli"))
    assert codex.cost_per_call_cents == 12.0
    assert codex.tokens_per_call == 1200.0
    assert codex.decisions == %{"allow" => 1}

    assert Enum.any?(comparison.recommendations, &String.contains?(&1, "Compare source"))
  end

  test "recommendations/1 prioritizes health, problem, proof, and cost actions" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Recommendation finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.recommendation"
    })

    assert {:ok, _invocation} =
             %Invocation{}
             |> Invocation.changeset(%{
               session_id: session.id,
               source: "codex-cli",
               tool: "ck_validate",
               provider: "openai",
               model: "gpt-5.5",
               input_tokens: 1_000,
               output_tokens: 250,
               estimated_cost_cents: 10,
               decision: "allow",
               metadata: %{}
             })
             |> Repo.insert()

    recommendations = Observability.recommendations(workspace_id: session.workspace_id)

    assert recommendations.health == "red"
    assert recommendations.count >= 3
    assert "problem" in recommendations.categories
    assert "cost" in recommendations.categories

    assert Enum.any?(recommendations.actions, &(&1.id == "health-red-runs"))

    assert Enum.any?(
             recommendations.actions,
             &(&1.title == "Regression eval for security.recommendation")
           )

    assert Enum.any?(
             recommendations.actions,
             &String.contains?(&1.suggested_action, "cost per successful task")
           )
  end

  test "eval_candidates/1 turns grouped problems into advisory backlog items" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Eval candidate finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.eval_candidate"
    })

    eval_candidates = Observability.eval_candidates(workspace_id: session.workspace_id)

    assert eval_candidates.health == "red"
    assert eval_candidates.count == 1
    assert [candidate] = eval_candidates.candidates
    assert candidate.title == "Regression eval for security.eval_candidate"
    assert candidate.priority == "critical"
    assert candidate.benchmark_hint == "security-regression"
    assert candidate.example_session_id == session.id
    assert candidate.human_gate_required == true
    assert candidate.links.problems == "/observability/problems"
    assert candidate.links.benchmarks == "/benchmarks"
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

  test "workspace_overview/1 summarizes recent runs, problems, costs, and recommendations" do
    workspace = workspace_fixture()
    session = session_fixture(%{workspace: workspace, budget_cents: 2_000, spent_cents: 450})
    task_fixture(%{session: session, status: "in_progress"})

    finding_fixture(%{
      session: session,
      title: "Overview finding",
      severity: "critical",
      status: "blocked",
      category: "security",
      rule_id: "security.overview"
    })

    overview = Observability.workspace_overview(workspace_id: workspace.id)

    assert overview.health.status == "red"
    assert overview.workspace.id == workspace.id
    assert overview.runs.count == 1
    assert [%{id: id, health: "red"}] = overview.runs.recent
    assert id == session.id
    assert overview.problems.count == 1
    assert [%{rule_id: "security.overview"}] = overview.problems.top
    assert overview.costs.spent_cents == 450
    assert overview.costs.budget_cents == 2_000
    assert overview.telemetry.import_mode == "dry_run_only"
    assert overview.telemetry.integrity == "sha256"
    assert Enum.any?(overview.recommendations, &String.contains?(&1, "red session runs"))
  end

  test "session_run/1 returns not_found for unknown sessions" do
    assert {:error, :not_found} = Observability.session_run(999_999)
  end

  test "telemetry export builds a redacted local-first envelope" do
    session = session_fixture()

    finding_fixture(%{
      session: session,
      title: "Exported issue",
      severity: "high",
      status: "open",
      category: "security",
      rule_id: "security.exported_issue"
    })

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    assert envelope.schema_version == ObservabilityTelemetry.schema_version()
    assert envelope.exported_at == "2026-04-29T04:00:00Z"
    assert envelope.session_run.session.id == session.id
    assert envelope.problems.count == 1
    assert envelope.redaction.policy == "summary_only"
    assert envelope.redaction.raw_context_bodies == false
    assert envelope.redaction.raw_memory_bodies == false
    assert envelope.integrity.session_id == session.id
    assert envelope.integrity.import_mutation_allowed == false
    assert envelope.integrity.fingerprint_algorithm == "sha256"
    assert envelope.integrity.payload_sha256 =~ ~r/^[a-f0-9]{64}$/
  end

  test "telemetry import preview validates an envelope without mutating storage" do
    session = session_fixture()
    session_count = Repo.aggregate(Session, :count, :id)
    finding_count = Repo.aggregate(Finding, :count, :id)

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    path =
      Path.join(System.tmp_dir!(), "controlkeel-observability-#{System.unique_integer()}.json")

    File.write!(path, Jason.encode!(envelope))

    assert {:ok, preview} = ObservabilityTelemetry.import_preview(path, dry_run: true)

    assert preview.dry_run == true
    assert preview.mutation == "none"
    assert preview.session_id == session.id
    assert preview.schema_version == ObservabilityTelemetry.schema_version()
    assert preview.integrity_status == "verified"
    assert preview.payload_sha256 == envelope.integrity.payload_sha256
    assert Repo.aggregate(Session, :count, :id) == session_count
    assert Repo.aggregate(Finding, :count, :id) == finding_count
  end

  test "telemetry import preview detects integrity mismatches" do
    session = session_fixture()

    assert {:ok, envelope} =
             ObservabilityTelemetry.export_session(session.id,
               exported_at: ~U[2026-04-29 04:00:00Z]
             )

    tampered =
      envelope
      |> Jason.encode!()
      |> Jason.decode!()
      |> put_in(["session_run", "health", "status"], "red")

    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-tampered-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(tampered))

    assert {:ok, preview} = ObservabilityTelemetry.import_preview(path, dry_run: true)
    assert preview.integrity_status == "mismatch"
  end

  test "telemetry import preview rejects invalid envelopes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-observability-invalid-#{System.unique_integer()}.json"
      )

    File.write!(path, Jason.encode!(%{"schema_version" => "wrong"}))

    assert {:error, :dry_run_required} = ObservabilityTelemetry.import_preview(path)

    assert {:error, {:missing_keys, missing}} =
             ObservabilityTelemetry.import_preview(path, dry_run: true)

    assert "session_run" in missing
  end
end
