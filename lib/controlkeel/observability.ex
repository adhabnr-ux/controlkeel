defmodule ControlKeel.Observability do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Budget
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Mission
  alias ControlKeel.Mission.{Finding, Session}
  alias ControlKeel.Repo

  @active_finding_statuses ~w(open blocked escalated)
  @active_task_statuses ~w(queued in_progress blocked paused)

  def problems(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    findings = problem_findings(opts)

    groups =
      findings
      |> Enum.group_by(&problem_key/1)
      |> Enum.map(fn {key, group} -> problem_summary(key, group) end)
      |> Enum.sort_by(&{health_rank(&1.health), severity_rank(&1.severity), &1.count}, :desc)
      |> Enum.take(limit)

    %{
      count: length(groups),
      total_findings: length(findings),
      problems: groups,
      health: problems_health(groups),
      recommendations: problems_recommendations(groups)
    }
  end

  def session_run(session_or_id, opts \\ [])

  def session_run(%Session{} = session, opts) do
    session = ensure_preloaded(session)
    events_limit = Keyword.get(opts, :events_limit, 8)
    events = Mission.list_session_events(session.id, events_limit)
    budget = budget_status(session)
    findings = session.findings || []
    tasks = session.tasks || []
    reviews = session.reviews || []
    invocations = session.invocations || []
    proofs = Mission.latest_proof_bundles_for_session(session.id)
    memory_count = memory_count(session.id)
    health = health(findings, tasks, reviews, budget)

    %{
      session: session_summary(session),
      health: health,
      budget: budget,
      findings: finding_summary(findings),
      tasks: task_summary(tasks),
      gates: gate_summary(reviews),
      timeline: timeline_summary(events),
      memory: %{records: memory_count},
      proofs: proof_summary(proofs),
      hosts_models_tools: invocation_summary(invocations),
      recommendations: recommendations(health, findings, reviews, budget, memory_count)
    }
  end

  def session_run(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_context(session_id) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, session_run(session, opts)}
    end
  end

  def session_run(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> session_run(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  defp problem_findings(opts) do
    base = from(f in Finding, join: s in assoc(f, :session), preload: [session: s])

    base
    |> maybe_filter_session(Keyword.get(opts, :session_id))
    |> maybe_filter_workspace(Keyword.get(opts, :workspace_id))
    |> where([f, _s], f.status in ^@active_finding_statuses)
    |> order_by([f, _s], desc: f.inserted_at)
    |> Repo.all()
  end

  defp maybe_filter_session(query, nil), do: query

  defp maybe_filter_session(query, session_id),
    do: where(query, [f, _s], f.session_id == ^session_id)

  defp maybe_filter_workspace(query, nil), do: query

  defp maybe_filter_workspace(query, workspace_id),
    do: where(query, [_f, s], s.workspace_id == ^workspace_id)

  defp problem_key(finding),
    do: {finding.rule_id || "unknown_rule", finding.category || "uncategorized"}

  defp problem_summary({rule_id, category}, findings) do
    severities = Enum.map(findings, &(&1.severity || "low"))
    statuses = Enum.map(findings, &(&1.status || "open"))
    severity = Enum.max_by(severities, &severity_rank/1, fn -> "low" end)
    status_counts = Enum.frequencies(statuses)
    health = problem_health(severity, status_counts)
    affected_sessions = findings |> Enum.map(& &1.session_id) |> Enum.uniq()
    latest = Enum.max_by(findings, &(&1.inserted_at || ~U[1970-01-01 00:00:00Z]), fn -> nil end)

    %{
      key: "#{rule_id}:#{category}",
      title: (latest && latest.title) || rule_id,
      rule_id: rule_id,
      category: category,
      severity: severity,
      health: health,
      count: length(findings),
      status_counts: status_counts,
      affected_sessions: affected_sessions,
      affected_session_count: length(affected_sessions),
      last_seen: latest && format_datetime(latest.inserted_at),
      recommendation: problem_recommendation(health, severity, rule_id),
      feedback_loop: feedback_loop(rule_id, category, severity, health, findings),
      examples:
        findings
        |> Enum.take(3)
        |> Enum.map(fn finding ->
          %{
            id: finding.id,
            title: finding.title,
            plain_message: finding.plain_message,
            severity: finding.severity,
            status: finding.status,
            session_id: finding.session_id,
            session_title: finding.session && finding.session.title,
            inserted_at: format_datetime(finding.inserted_at)
          }
        end)
    }
  end

  defp problem_health("critical", _status_counts), do: "red"
  defp problem_health(_severity, %{"blocked" => count}) when count > 0, do: "red"
  defp problem_health("high", _status_counts), do: "yellow"
  defp problem_health(_severity, %{"escalated" => count}) when count > 0, do: "yellow"
  defp problem_health(_severity, _status_counts), do: "yellow"

  defp health_rank("red"), do: 3
  defp health_rank("yellow"), do: 2
  defp health_rank("green"), do: 1
  defp health_rank(_), do: 0

  defp severity_rank("critical"), do: 4
  defp severity_rank("high"), do: 3
  defp severity_rank("medium"), do: 2
  defp severity_rank("low"), do: 1
  defp severity_rank(_), do: 0

  defp problems_health([]), do: "green"

  defp problems_health(groups) do
    cond do
      Enum.any?(groups, &(&1.health == "red")) -> "red"
      Enum.any?(groups, &(&1.health == "yellow")) -> "yellow"
      true -> "green"
    end
  end

  defp feedback_loop(rule_id, category, severity, health, findings) do
    example = List.first(findings)

    %{
      eval_candidate_title: "Regression eval for #{rule_id}",
      evidence_kind: "finding_group",
      evidence_summary:
        "#{length(findings)} active #{category} finding(s), highest severity #{severity}, health #{health}.",
      suggested_action: feedback_action(health, rule_id),
      benchmark_hint: benchmark_hint(category, rule_id),
      human_gate_required: true,
      example_session_id: example && example.session_id,
      example_finding_id: example && example.id
    }
  end

  defp feedback_action("red", rule_id),
    do: "Add or run a regression benchmark for #{rule_id} before widening automation."

  defp feedback_action(_health, rule_id),
    do: "Create a lightweight eval case for #{rule_id} and monitor recurrence."

  defp benchmark_hint("security", _rule_id), do: "security-regression"
  defp benchmark_hint("review", _rule_id), do: "governance-gate-regression"
  defp benchmark_hint("integration", _rule_id), do: "integration-continuity-regression"
  defp benchmark_hint(_category, rule_id), do: "#{rule_id}-regression"

  defp problem_recommendation("red", _severity, rule_id),
    do: "Resolve or explicitly approve #{rule_id} before widening automation."

  defp problem_recommendation("yellow", _severity, rule_id),
    do: "Review #{rule_id}, add regression coverage, and confirm the affected sessions."

  defp problem_recommendation(_health, _severity, rule_id),
    do: "Monitor #{rule_id} for recurrence."

  defp problems_recommendations([]), do: ["No active problems detected."]

  defp problems_recommendations(groups) do
    groups
    |> Enum.take(3)
    |> Enum.map(& &1.recommendation)
  end

  defp ensure_preloaded(%Session{workspace: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{tasks: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{findings: %Ecto.Association.NotLoaded{}} = session),
    do: Mission.get_session_context(session.id)

  defp ensure_preloaded(%Session{} = session), do: session

  defp budget_status(session) do
    case Budget.status(%{"session_id" => session.id}) do
      {:ok, budget} -> budget
      _ -> %{}
    end
  end

  defp session_summary(session) do
    %{
      id: session.id,
      title: session.title,
      objective: session.objective,
      risk_tier: session.risk_tier,
      status: session.status,
      workspace_id: session.workspace_id,
      workspace_name: session.workspace && session.workspace.name
    }
  end

  defp health(findings, tasks, reviews, budget) do
    active_findings = Enum.filter(findings, &(&1.status in @active_finding_statuses))
    critical = Enum.count(active_findings, &(&1.severity == "critical"))
    high = Enum.count(active_findings, &(&1.severity == "high"))
    blocked = Enum.count(active_findings, &(&1.status == "blocked"))
    pending_reviews = Enum.count(reviews, &(&1.status == "pending"))
    active_tasks = Enum.count(tasks, &(&1.status in @active_task_statuses))

    status =
      cond do
        Map.get(budget, "decision") == "block" or critical > 0 or blocked > 0 -> "red"
        Map.get(budget, "decision") == "warn" or high > 0 or pending_reviews > 0 -> "yellow"
        active_findings != [] or active_tasks > 0 -> "yellow"
        true -> "green"
      end

    %{
      status: status,
      label: health_label(status),
      reasons: health_reasons(status, critical, high, blocked, pending_reviews, budget)
    }
  end

  defp health_label("red"), do: "Needs intervention"
  defp health_label("yellow"), do: "Needs attention"
  defp health_label("green"), do: "Healthy"

  defp health_reasons(status, critical, high, blocked, pending_reviews, budget) do
    []
    |> maybe_reason(critical > 0, "#{critical} critical finding(s)")
    |> maybe_reason(blocked > 0, "#{blocked} blocked finding(s)")
    |> maybe_reason(high > 0, "#{high} high finding(s)")
    |> maybe_reason(pending_reviews > 0, "#{pending_reviews} pending review gate(s)")
    |> maybe_reason(
      Map.get(budget, "decision") in ["warn", "block"],
      "budget #{Map.get(budget, "decision")}"
    )
    |> case do
      [] -> [health_label(status)]
      reasons -> reasons
    end
  end

  defp maybe_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_reason(reasons, false, _reason), do: reasons

  defp finding_summary(findings) do
    active = Enum.filter(findings, &(&1.status in @active_finding_statuses))

    %{
      total: length(findings),
      active: length(active),
      blocked: Enum.count(findings, &(&1.status == "blocked")),
      critical: Enum.count(active, &(&1.severity == "critical")),
      high: Enum.count(active, &(&1.severity == "high")),
      by_severity: frequencies(active, & &1.severity),
      recent:
        findings
        |> Enum.take(5)
        |> Enum.map(fn finding ->
          %{
            id: finding.id,
            title: finding.title,
            severity: finding.severity,
            status: finding.status,
            rule_id: finding.rule_id
          }
        end)
    }
  end

  defp task_summary(tasks) do
    %{
      total: length(tasks),
      active: Enum.count(tasks, &(&1.status in @active_task_statuses)),
      by_status: frequencies(tasks, & &1.status)
    }
  end

  defp gate_summary(reviews) do
    %{
      total_reviews: length(reviews),
      pending_reviews: Enum.count(reviews, &(&1.status == "pending")),
      latest:
        reviews
        |> Enum.take(3)
        |> Enum.map(fn review ->
          %{
            id: review.id,
            status: review.status,
            review_type: review.review_type,
            title: review.title || "Review #{review.id}"
          }
        end)
    }
  end

  defp timeline_summary(events) do
    %{
      count: length(events),
      recent:
        Enum.map(events, fn event ->
          %{
            id: event_value(event, :id),
            event_type: event_value(event, :event_type),
            actor: event_value(event, :actor),
            summary: event_value(event, :summary),
            inserted_at: format_datetime(event_value(event, :inserted_at))
          }
        end)
    }
  end

  defp proof_summary(proofs) when is_map(proofs) do
    %{
      count: map_size(proofs),
      task_ids: Map.keys(proofs)
    }
  end

  defp invocation_summary(invocations) do
    total_cost = Enum.reduce(invocations, 0, &(&1.estimated_cost_cents + &2))

    %{
      invocations: length(invocations),
      estimated_cost_cents: total_cost,
      by_source: frequencies(invocations, &(&1.source || "unknown")),
      by_model: frequencies(invocations, &(&1.model || "unknown")),
      by_tool: frequencies(invocations, &(&1.tool || "unknown"))
    }
  end

  defp recommendations(health, findings, reviews, budget, memory_count) do
    []
    |> maybe_reason(
      health.status == "red",
      "Resolve blocked or critical findings before widening automation."
    )
    |> maybe_reason(
      health.status == "yellow",
      "Review active findings, pending gates, or budget warnings before calling the run healthy."
    )
    |> maybe_reason(
      Enum.any?(reviews, &(&1.status == "pending")),
      "Finish pending human review gates or narrow the plan."
    )
    |> maybe_reason(
      Map.get(budget, "decision") == "warn",
      "Check cost efficiency before running expensive agent loops."
    )
    |> maybe_reason(
      memory_count == 0,
      "Record key decisions in CK memory so future hosts can resume with context."
    )
    |> maybe_reason(findings == [], "No findings recorded yet; run validation before shipping.")
    |> case do
      [] -> ["Run is observable and no immediate action is required."]
      recommendations -> recommendations
    end
  end

  defp event_value(event, key) when is_map(event),
    do: Map.get(event, key) || Map.get(event, Atom.to_string(key))

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp memory_count(session_id) do
    MemoryRecord
    |> where([r], r.session_id == ^session_id and is_nil(r.archived_at))
    |> Repo.aggregate(:count, :id)
  end

  defp frequencies(items, fun) do
    items
    |> Enum.map(fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end
end
