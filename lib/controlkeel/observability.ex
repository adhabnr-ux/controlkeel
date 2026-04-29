defmodule ControlKeel.Observability do
  @moduledoc false

  import Ecto.Query, warn: false

  alias ControlKeel.Budget
  alias ControlKeel.Memory.Record, as: MemoryRecord
  alias ControlKeel.Mission
  alias ControlKeel.Observability.{BenchmarkDraft, EvalCandidate, ImportedEnvelope}
  alias ControlKeel.Mission.{Finding, Invocation, Session}
  alias ControlKeel.Repo

  @active_finding_statuses ~w(open blocked escalated)
  @active_task_statuses ~w(queued in_progress blocked paused)
  @cost_group_fields ~w(model tool source provider)

  def workspace_overview(opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    sessions = recent_sessions(opts, limit)
    runs = Enum.map(sessions, &session_run(&1.id, events_limit: 3))

    run_summaries =
      runs
      |> Enum.flat_map(fn
        {:ok, run} -> [overview_run_summary(run)]
        _other -> []
      end)

    workspace_id =
      Keyword.get(opts, :workspace_id) ||
        run_summaries |> List.first() |> then(&(&1 && &1.workspace_id))

    problems_opts = if workspace_id, do: [workspace_id: workspace_id, limit: 5], else: [limit: 5]
    problem_summary = problems(problems_opts)
    health = overview_health(run_summaries, problem_summary)

    %{
      health: health,
      workspace: overview_workspace(run_summaries),
      runs: %{
        count: length(run_summaries),
        recent: run_summaries
      },
      problems: %{
        health: problem_summary.health,
        count: problem_summary.count,
        total_findings: problem_summary.total_findings,
        top: problem_summary.problems,
        recommendations: problem_summary.recommendations
      },
      costs: overview_costs(run_summaries),
      telemetry: overview_telemetry(workspace_id),
      recommendations: overview_recommendations(health, run_summaries, problem_summary)
    }
  end

  def imports(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    snapshots = imported_envelopes(opts, limit)

    %{
      count: imported_envelope_count(opts),
      limit: limit,
      recent: Enum.map(snapshots, &import_summary/1),
      by_integrity: frequencies(snapshots, &(&1.integrity_status || "unknown")),
      by_health: frequencies(snapshots, &(&1.health || "unknown")),
      recommendations: import_recommendations(snapshots)
    }
  end

  def trends(opts \\ []) do
    days = opts |> Keyword.get(:days, 7) |> normalize_days()
    workspace_id = Keyword.get(opts, :workspace_id)
    today = Date.utc_today()
    start_date = Date.add(today, -(days - 1))
    since = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")

    sessions = trend_sessions(workspace_id, since)
    findings = trend_findings(workspace_id, since)
    invocations = trend_invocations(workspace_id, since)
    imports = trend_imports(workspace_id, since)

    series = trend_series(today, days, sessions, findings, invocations, imports)
    totals = trend_totals(series)

    %{
      days: days,
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(today),
      totals: totals,
      series: series,
      recommendations: trend_recommendations(series, totals)
    }
  end

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

  def costs(opts \\ []) do
    by = normalize_cost_group(Keyword.get(opts, :by, "model"))
    invocations = cost_invocations(opts)
    totals = cost_totals(invocations)
    groups = cost_groups(invocations, by)

    %{
      by: by,
      totals: totals,
      groups: groups,
      recommendations: cost_recommendations(totals, groups, by),
      available_groupings: @cost_group_fields
    }
  end

  def comparison(opts \\ []) do
    by = normalize_cost_group(Keyword.get(opts, :by, "model"))
    invocations = cost_invocations(opts)
    groups = comparison_groups(invocations, by)

    %{
      by: by,
      totals: cost_totals(invocations),
      groups: groups,
      available_groupings: @cost_group_fields,
      recommendations: comparison_recommendations(groups, by)
    }
  end

  def saved_eval_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    candidates = saved_eval_candidate_records(opts, limit)

    %{
      count: saved_eval_candidate_count(opts),
      limit: limit,
      candidates: Enum.map(candidates, &saved_eval_candidate_summary/1),
      by_status: frequencies(candidates, &(&1.status || "unknown")),
      by_priority: frequencies(candidates, &(&1.priority || "unknown")),
      recommendations: saved_eval_candidate_recommendations(candidates)
    }
  end

  def save_eval_candidates(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)
    derived = eval_candidates(if(workspace_id, do: [workspace_id: workspace_id], else: []))

    results =
      Enum.map(derived.candidates, fn candidate ->
        save_eval_candidate(candidate, workspace_id)
      end)

    %{
      source_count: derived.count,
      stored: Enum.count(results, &match?({:stored, _}, &1)),
      existing: Enum.count(results, &match?({:existing, _}, &1)),
      candidates:
        Enum.map(results, fn {_status, record} -> saved_eval_candidate_summary(record) end),
      human_gate_required: true,
      mutation: "advisory_record_only"
    }
  end

  def benchmark_drafts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    drafts = benchmark_draft_records(opts, limit)

    %{
      count: benchmark_draft_count(opts),
      limit: limit,
      drafts: Enum.map(drafts, &benchmark_draft_summary/1),
      by_status: frequencies(drafts, &(&1.status || "unknown")),
      by_suite: frequencies(drafts, &(&1.suite_slug || "unknown")),
      recommendations: benchmark_draft_recommendations(drafts)
    }
  end

  def generate_benchmark_drafts(opts \\ []) do
    workspace_id = Keyword.get(opts, :workspace_id)

    candidates =
      EvalCandidate
      |> maybe_filter_eval_workspace(workspace_id)
      |> maybe_filter_eval_status("open")
      |> order_by([c], desc: c.inserted_at, desc: c.id)
      |> Repo.all()

    results = Enum.map(candidates, &generate_benchmark_draft/1)

    %{
      source_count: length(candidates),
      stored: Enum.count(results, &match?({:stored, _}, &1)),
      existing: Enum.count(results, &match?({:existing, _}, &1)),
      drafts: Enum.map(results, fn {_status, draft} -> benchmark_draft_summary(draft) end),
      human_gate_required: true,
      mutation: "draft_record_only"
    }
  end

  def recommendations(opts \\ []) do
    overview = workspace_overview(opts)
    workspace_id = overview.workspace.id
    scoped_opts = if workspace_id, do: [workspace_id: workspace_id], else: []
    problems = problems(Keyword.put(scoped_opts, :limit, 5))
    costs = costs(scoped_opts)

    actions =
      []
      |> add_health_actions(overview)
      |> add_problem_actions(problems)
      |> add_cost_actions(costs)
      |> Enum.sort_by(&{priority_rank(&1.priority), &1.id})

    %{
      health: recommendation_health(actions),
      count: length(actions),
      actions: actions,
      categories: actions |> Enum.map(& &1.category) |> Enum.uniq(),
      workspace: overview.workspace
    }
  end

  def eval_candidates(opts \\ []) do
    problem_summary = problems(opts)

    candidates =
      problem_summary.problems
      |> Enum.map(&eval_candidate_from_problem/1)
      |> Enum.sort_by(&{priority_rank(&1.priority), &1.rule_id})

    %{
      count: length(candidates),
      health: eval_candidates_health(candidates),
      candidates: candidates,
      recommendations: eval_candidate_recommendations(candidates)
    }
  end

  def timeline(session_or_id, opts \\ [])

  def timeline(%Session{} = session, opts) do
    session = ensure_preloaded(session)
    limit = Keyword.get(opts, :limit, 50)
    events = Mission.list_session_events(session.id, limit)
    event_summaries = Enum.map(events, &timeline_event/1)

    %{
      session: session_summary(session),
      count: length(event_summaries),
      limit: limit,
      by_event_type: frequencies(event_summaries, & &1.event_type),
      by_actor: frequencies(event_summaries, & &1.actor),
      events: event_summaries
    }
  end

  def timeline(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_context(session_id) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, timeline(session, opts)}
    end
  end

  def timeline(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> timeline(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  def memory_context(session_or_id, opts \\ [])

  def memory_context(%Session{} = session, opts) do
    session = ensure_preloaded(session)
    limit = Keyword.get(opts, :limit, 10)
    records = memory_records(session.id, limit)
    active_records = Enum.filter(records, &is_nil(&1.archived_at))
    archived_records = Enum.reject(records, &is_nil(&1.archived_at))

    %{
      session: session_summary(session),
      context: %{
        tasks: length(session.tasks || []),
        findings: length(session.findings || []),
        reviews: length(session.reviews || []),
        invocations: length(session.invocations || [])
      },
      memory: %{
        count: length(records),
        active: length(active_records),
        archived: length(archived_records),
        by_type: frequencies(records, &(&1.record_type || "unknown")),
        by_source: frequencies(records, &(&1.source_type || "unknown")),
        recent: Enum.map(records, &memory_record_summary/1)
      },
      recommendations: memory_context_recommendations(active_records, archived_records)
    }
  end

  def memory_context(session_id, opts) when is_integer(session_id) do
    case Mission.get_session_context(session_id) do
      nil -> {:error, :not_found}
      %Session{} = session -> {:ok, memory_context(session, opts)}
    end
  end

  def memory_context(session_id, opts) when is_binary(session_id) do
    case Integer.parse(session_id) do
      {parsed, ""} -> memory_context(parsed, opts)
      _ -> {:error, :invalid_session_id}
    end
  end

  def memory_quality(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    stale_days = opts |> Keyword.get(:stale_days, 30) |> normalize_stale_days()
    workspace_id = Keyword.get(opts, :workspace_id)
    records = memory_quality_records(workspace_id)

    sessions =
      recent_sessions([workspace_id: workspace_id], Keyword.get(opts, :session_limit, 20))

    active_records = Enum.filter(records, &is_nil(&1.archived_at))
    archived_records = Enum.reject(records, &is_nil(&1.archived_at))
    stale = stale_memory_candidates(active_records, stale_days, limit)
    duplicates = duplicate_memory_clusters(active_records, limit)
    contradictions = contradiction_memory_candidates(active_records, limit)
    missed = missed_memory_sessions(sessions, records, limit)

    %{
      stale_days: stale_days,
      totals: %{
        records: length(records),
        active: length(active_records),
        archived: length(archived_records),
        stale_candidates: length(stale),
        duplicate_clusters: length(duplicates),
        contradiction_candidates: length(contradictions),
        missed_memory_sessions: length(missed)
      },
      distributions: %{
        by_type: frequencies(records, &(&1.record_type || "unknown")),
        by_source: frequencies(records, &(&1.source_type || "unknown"))
      },
      stale_candidates: stale,
      duplicate_clusters: duplicates,
      contradiction_candidates: contradictions,
      missed_memory_sessions: missed,
      recommendations:
        memory_quality_recommendations(stale, duplicates, contradictions, missed, records)
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

  defp normalize_stale_days(days) when is_integer(days) and days > 0 and days <= 365, do: days
  defp normalize_stale_days(days) when is_integer(days) and days > 365, do: 365
  defp normalize_stale_days(_days), do: 30

  defp memory_quality_records(workspace_id) do
    MemoryRecord
    |> maybe_filter_memory_workspace(workspace_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Repo.all()
  end

  defp maybe_filter_memory_workspace(query, nil), do: query

  defp maybe_filter_memory_workspace(query, workspace_id),
    do: where(query, [m], m.workspace_id == ^workspace_id)

  defp stale_memory_candidates(records, stale_days, limit) do
    today = Date.utc_today()

    records
    |> Enum.map(fn record -> {record, memory_age_days(record, today)} end)
    |> Enum.filter(fn {_record, age_days} -> age_days >= stale_days end)
    |> Enum.sort_by(fn {_record, age_days} -> age_days end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {record, age_days} -> memory_quality_record_summary(record, age_days) end)
  end

  defp memory_age_days(record, today) do
    case record.inserted_at do
      %DateTime{} = inserted_at -> Date.diff(today, DateTime.to_date(inserted_at))
      %NaiveDateTime{} = inserted_at -> Date.diff(today, NaiveDateTime.to_date(inserted_at))
      _ -> 0
    end
  end

  defp duplicate_memory_clusters(records, limit) do
    records
    |> Enum.group_by(&memory_duplicate_key/1)
    |> Enum.reject(fn {key, group} -> key == "" or length(group) < 2 end)
    |> Enum.map(fn {key, group} ->
      %{
        key: key,
        count: length(group),
        records: group |> Enum.take(5) |> Enum.map(&memory_quality_record_summary(&1, nil))
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end

  defp memory_duplicate_key(record) do
    [record.title, record.summary]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" | ")
    |> String.downcase()
  end

  defp contradiction_memory_candidates(records, limit) do
    records
    |> Enum.filter(&contradiction_marker?/1)
    |> Enum.take(limit)
    |> Enum.map(&memory_quality_record_summary(&1, nil))
  end

  defp contradiction_marker?(record) do
    text =
      [record.title, record.summary | List.wrap(record.tags)]
      |> Enum.concat(record.metadata |> Map.keys() |> Enum.map(&to_string/1))
      |> Enum.concat(record.metadata |> Map.values() |> Enum.map(&to_string/1))
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    Enum.any?(["contradict", "superseded", "obsolete", "conflict"], &String.contains?(text, &1))
  end

  defp missed_memory_sessions(sessions, records, limit) do
    memory_session_ids =
      records
      |> Enum.filter(&(&1.record_type in ["brief", "checkpoint", "decision", "goal"]))
      |> Enum.map(& &1.session_id)
      |> MapSet.new()

    sessions
    |> Enum.reject(&MapSet.member?(memory_session_ids, &1.id))
    |> Enum.map(fn session -> {session, session_evidence_counts(session.id)} end)
    |> Enum.filter(fn {_session, counts} ->
      counts.findings > 0 or counts.reviews > 0 or counts.invocations > 0
    end)
    |> Enum.take(limit)
    |> Enum.map(fn {session, counts} ->
      %{
        id: session.id,
        title: session.title,
        findings: counts.findings,
        reviews: counts.reviews,
        invocations: counts.invocations,
        recommendation: "Record a checkpoint or decision memory for this session's evidence."
      }
    end)
  end

  defp session_evidence_counts(session_id) do
    %{
      findings:
        Repo.aggregate(from(f in Finding, where: f.session_id == ^session_id), :count, :id),
      reviews:
        Repo.aggregate(
          from(r in ControlKeel.Mission.Review, where: r.session_id == ^session_id),
          :count,
          :id
        ),
      invocations:
        Repo.aggregate(from(i in Invocation, where: i.session_id == ^session_id), :count, :id)
    }
  end

  defp memory_quality_record_summary(record, age_days) do
    %{
      id: record.id,
      title: record.title,
      summary: record.summary,
      record_type: record.record_type,
      source_type: record.source_type,
      session_id: record.session_id,
      task_id: record.task_id,
      tags: record.tags || [],
      archived: not is_nil(record.archived_at),
      inserted_at: format_datetime(record.inserted_at),
      age_days: age_days
    }
  end

  defp memory_quality_recommendations(stale, duplicates, contradictions, missed, records) do
    []
    |> maybe_reason(
      records == [],
      "No memory records exist yet; record checkpoints and decisions for durable continuity."
    )
    |> maybe_reason(
      stale != [],
      "Review stale memory candidates and archive or supersede records that no longer match current behavior."
    )
    |> maybe_reason(
      duplicates != [],
      "Deduplicate repeated memory records to reduce retrieval noise."
    )
    |> maybe_reason(
      contradictions != [],
      "Review contradiction or superseded memory candidates before relying on retrieved context."
    )
    |> maybe_reason(
      missed != [],
      "Add checkpoint or decision memory for sessions with evidence but no durable memory."
    )
    |> case do
      [] -> ["Memory quality signals look stable for this workspace."]
      recommendations -> recommendations
    end
  end

  defp normalize_days(days) when is_integer(days) and days > 0 and days <= 90, do: days
  defp normalize_days(days) when is_integer(days) and days > 90, do: 90
  defp normalize_days(_days), do: 7

  defp trend_sessions(workspace_id, since) do
    Session
    |> maybe_filter_session_workspace(workspace_id)
    |> where([s], s.inserted_at >= ^since)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> Repo.all()
    |> Enum.map(&ensure_preloaded/1)
  end

  defp trend_findings(workspace_id, since) do
    Finding
    |> join(:inner, [f], s in assoc(f, :session))
    |> maybe_filter_workspace(workspace_id)
    |> where([f, _s], f.inserted_at >= ^since)
    |> where([f, _s], f.status in ^@active_finding_statuses)
    |> Repo.all()
  end

  defp trend_invocations(workspace_id, since) do
    Invocation
    |> join(:inner, [i], s in assoc(i, :session))
    |> maybe_filter_invocation_workspace(workspace_id)
    |> where([i, _s], i.inserted_at >= ^since)
    |> Repo.all()
  end

  defp trend_imports(workspace_id, since) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(workspace_id)
    |> where([i], i.imported_at >= ^since)
    |> Repo.all()
  end

  defp trend_series(today, days, sessions, findings, invocations, imports) do
    session_groups = Enum.group_by(sessions, &day_key(&1.inserted_at))
    finding_groups = Enum.group_by(findings, &day_key(&1.inserted_at))
    invocation_groups = Enum.group_by(invocations, &day_key(&1.inserted_at))
    import_groups = Enum.group_by(imports, &day_key(&1.imported_at))

    0..(days - 1)
    |> Enum.map(fn offset -> Date.add(today, -(days - 1 - offset)) end)
    |> Enum.map(fn date ->
      key = Date.to_iso8601(date)
      day_sessions = Map.get(session_groups, key, [])
      day_findings = Map.get(finding_groups, key, [])
      day_invocations = Map.get(invocation_groups, key, [])
      day_imports = Map.get(import_groups, key, [])
      health_counts = frequencies(day_sessions, &session_health_status/1)

      %{
        date: key,
        runs: length(day_sessions),
        health: %{
          red: Map.get(health_counts, "red", 0),
          yellow: Map.get(health_counts, "yellow", 0),
          green: Map.get(health_counts, "green", 0)
        },
        active_findings: length(day_findings),
        blocked_findings: Enum.count(day_findings, &(&1.status == "blocked")),
        estimated_cost_cents: sum_invocation_field(day_invocations, :estimated_cost_cents),
        imports: length(day_imports),
        verified_imports: Enum.count(day_imports, &(&1.integrity_status == "verified")),
        non_verified_imports: Enum.count(day_imports, &(&1.integrity_status != "verified"))
      }
    end)
  end

  defp session_health_status(session) do
    session = ensure_preloaded(session)
    findings = session.findings || []
    tasks = session.tasks || []
    reviews = session.reviews || []

    health(findings, tasks, reviews, budget_status(session)).status
  end

  defp trend_totals(series) do
    %{
      runs: Enum.reduce(series, 0, &(&1.runs + &2)),
      red_runs: Enum.reduce(series, 0, &(&1.health.red + &2)),
      yellow_runs: Enum.reduce(series, 0, &(&1.health.yellow + &2)),
      green_runs: Enum.reduce(series, 0, &(&1.health.green + &2)),
      active_findings: Enum.reduce(series, 0, &(&1.active_findings + &2)),
      blocked_findings: Enum.reduce(series, 0, &(&1.blocked_findings + &2)),
      estimated_cost_cents: Enum.reduce(series, 0, &(&1.estimated_cost_cents + &2)),
      imports: Enum.reduce(series, 0, &(&1.imports + &2)),
      verified_imports: Enum.reduce(series, 0, &(&1.verified_imports + &2)),
      non_verified_imports: Enum.reduce(series, 0, &(&1.non_verified_imports + &2))
    }
  end

  defp trend_recommendations(series, totals) do
    last_day = List.last(series) || %{}

    []
    |> maybe_reason(totals.runs == 0, "No session runs recorded in this trend window yet.")
    |> maybe_reason(
      totals.red_runs > 0,
      "Red runs appeared in the trend window; inspect blocked findings and gates before widening automation."
    )
    |> maybe_reason(
      totals.blocked_findings > 0,
      "Blocked findings are still present in the trend window; resolve or disposition them before promotion work."
    )
    |> maybe_reason(
      totals.imports == 0,
      "No persisted import snapshots in this trend window; persist verified exports to enable cross-run trend baselines."
    )
    |> maybe_reason(
      totals.non_verified_imports > 0,
      "Some imports are not verified; exclude them from benchmark evidence until resolved."
    )
    |> maybe_reason(
      (last_day[:estimated_cost_cents] || 0) > div(max(totals.estimated_cost_cents, 1), 2),
      "Recent estimated spend is concentrated in the latest day; review cost efficiency before scaling."
    )
    |> case do
      [] -> ["Local observability trends look stable for this window."]
      recommendations -> recommendations
    end
  end

  defp day_key(nil), do: "unknown"
  defp day_key(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp day_key(%NaiveDateTime{} = datetime),
    do: datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp overview_telemetry(workspace_id) do
    import_summary =
      imports(if(workspace_id, do: [workspace_id: workspace_id, limit: 3], else: [limit: 3]))

    %{
      export_schema_version: ControlKeel.Observability.Telemetry.schema_version(),
      import_mode: "dry_run_or_local_persist",
      integrity: "sha256",
      persisted_imports: import_summary.count,
      recent_imports: import_summary.recent
    }
  end

  defp imported_envelopes(opts, limit) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(Keyword.get(opts, :workspace_id))
    |> order_by([i], desc: i.imported_at, desc: i.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp imported_envelope_count(opts) do
    ImportedEnvelope
    |> maybe_filter_import_workspace(Keyword.get(opts, :workspace_id))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_import_workspace(query, nil), do: query

  defp maybe_filter_import_workspace(query, workspace_id),
    do: where(query, [i], i.workspace_id == ^workspace_id)

  defp import_summary(%ImportedEnvelope{} = imported) do
    %{
      id: imported.id,
      schema_version: imported.schema_version,
      exported_at: format_datetime(imported.exported_at),
      imported_at: format_datetime(imported.imported_at),
      original_session_id: imported.original_session_id,
      original_session_title: imported.original_session_title,
      health: imported.health || "unknown",
      problem_groups: imported.problem_groups || 0,
      total_problem_findings: imported.total_problem_findings || 0,
      redaction_policy: imported.redaction_policy,
      integrity_status: imported.integrity_status || "unknown",
      payload_sha256: imported.payload_sha256,
      payload_fingerprint: fingerprint_prefix(imported.payload_sha256),
      import_mode: imported.import_mode,
      source: imported.source || %{},
      mutation: "none",
      workspace_id: imported.workspace_id,
      session_id: imported.session_id
    }
  end

  defp fingerprint_prefix(nil), do: nil
  defp fingerprint_prefix(value) when is_binary(value), do: String.slice(value, 0, 12)

  defp import_recommendations([]) do
    [
      "No persisted observability imports yet; use `controlkeel obs import <file> --persist` after verifying an envelope."
    ]
  end

  defp import_recommendations(imports) do
    []
    |> maybe_reason(
      Enum.any?(imports, &(&1.integrity_status != "verified")),
      "Review imports with non-verified integrity before using them as benchmark evidence."
    )
    |> maybe_reason(
      Enum.any?(imports, &((&1.problem_groups || 0) > 0)),
      "Convert recurring imported problem groups into eval or benchmark coverage."
    )
    |> case do
      [] -> ["Imported observability snapshots are verified and ready for trend analysis."]
      recommendations -> recommendations
    end
  end

  defp recent_sessions(opts, limit) do
    workspace_id = Keyword.get(opts, :workspace_id)

    Session
    |> maybe_filter_session_workspace(workspace_id)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_session_workspace(query, nil), do: query

  defp maybe_filter_session_workspace(query, workspace_id),
    do: where(query, [s], s.workspace_id == ^workspace_id)

  defp overview_run_summary(run) do
    %{
      id: run.session.id,
      title: run.session.title,
      objective: run.session.objective,
      workspace_id: run.session.workspace_id,
      workspace_name: run.session.workspace_name,
      health: run.health.status,
      health_label: run.health.label,
      active_findings: run.findings.active,
      blocked_findings: run.findings.blocked,
      pending_gates: run.gates.pending_reviews,
      timeline_events: run.timeline.count,
      memory_records: run.memory.records,
      proof_bundles: run.proofs.count,
      invocations: run.hosts_models_tools.invocations,
      estimated_cost_cents: run.hosts_models_tools.estimated_cost_cents,
      budget_spent_cents: run.budget["spent_cents"] || 0,
      budget_limit_cents: run.budget["session_budget_cents"] || 0,
      recommendations: Enum.take(run.recommendations, 2)
    }
  end

  defp overview_workspace([]), do: %{id: nil, name: "No workspace"}

  defp overview_workspace([run | _runs]) do
    %{id: run.workspace_id, name: run.workspace_name || "Workspace #{run.workspace_id}"}
  end

  defp overview_health(runs, problems) do
    status =
      cond do
        Enum.any?(runs, &(&1.health == "red")) or problems.health == "red" -> "red"
        Enum.any?(runs, &(&1.health == "yellow")) or problems.health == "yellow" -> "yellow"
        runs == [] -> "yellow"
        true -> "green"
      end

    %{
      status: status,
      label: health_label(status),
      run_count: length(runs),
      red_runs: Enum.count(runs, &(&1.health == "red")),
      yellow_runs: Enum.count(runs, &(&1.health == "yellow")),
      green_runs: Enum.count(runs, &(&1.health == "green"))
    }
  end

  defp overview_costs(runs) do
    %{
      spent_cents: Enum.reduce(runs, 0, &(&1.budget_spent_cents + &2)),
      budget_cents: Enum.reduce(runs, 0, &(&1.budget_limit_cents + &2)),
      estimated_invocation_cents: Enum.reduce(runs, 0, &(&1.estimated_cost_cents + &2)),
      invocations: Enum.reduce(runs, 0, &(&1.invocations + &2))
    }
  end

  defp overview_recommendations(health, runs, problems) do
    []
    |> maybe_reason(runs == [], "No session runs are available yet.")
    |> maybe_reason(
      health.status == "red",
      "Prioritize red session runs and blocked findings before widening automation."
    )
    |> maybe_reason(
      problems.count > 0,
      "Review grouped problems and convert recurring failures into eval coverage."
    )
    |> maybe_reason(
      Enum.any?(runs, &(&1.pending_gates > 0)),
      "Clear pending review gates before marking runs healthy."
    )
    |> maybe_reason(
      Enum.any?(runs, &(&1.proof_bundles == 0)),
      "Generate proof bundles for runs that need reproducible evidence."
    )
    |> case do
      [] -> ["Workspace observability is healthy."]
      recommendations -> Enum.take(recommendations ++ problems.recommendations, 5)
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

  defp cost_invocations(opts) do
    base = from(i in Invocation, join: s in assoc(i, :session), preload: [session: s])

    base
    |> maybe_filter_invocation_session(Keyword.get(opts, :session_id))
    |> maybe_filter_invocation_workspace(Keyword.get(opts, :workspace_id))
    |> order_by([i, _s], desc: i.inserted_at, desc: i.id)
    |> Repo.all()
  end

  defp maybe_filter_invocation_session(query, nil), do: query

  defp maybe_filter_invocation_session(query, session_id),
    do: where(query, [i, _s], i.session_id == ^session_id)

  defp maybe_filter_invocation_workspace(query, nil), do: query

  defp maybe_filter_invocation_workspace(query, workspace_id),
    do: where(query, [_i, s], s.workspace_id == ^workspace_id)

  defp normalize_cost_group(group) when group in @cost_group_fields, do: group
  defp normalize_cost_group(_group), do: "model"

  defp cost_totals(invocations) do
    %{
      invocations: length(invocations),
      estimated_cost_cents: sum_invocation_field(invocations, :estimated_cost_cents),
      input_tokens: sum_invocation_field(invocations, :input_tokens),
      cached_input_tokens: sum_invocation_field(invocations, :cached_input_tokens),
      output_tokens: sum_invocation_field(invocations, :output_tokens),
      sessions: invocations |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()
    }
  end

  defp cost_groups(invocations, by) do
    invocations
    |> Enum.group_by(&cost_group_value(&1, by))
    |> Enum.map(fn {name, group} ->
      %{
        name: name,
        invocations: length(group),
        estimated_cost_cents: sum_invocation_field(group, :estimated_cost_cents),
        input_tokens: sum_invocation_field(group, :input_tokens),
        cached_input_tokens: sum_invocation_field(group, :cached_input_tokens),
        output_tokens: sum_invocation_field(group, :output_tokens),
        sessions: group |> Enum.map(& &1.session_id) |> Enum.uniq() |> length()
      }
    end)
    |> Enum.sort_by(&{&1.estimated_cost_cents, &1.invocations}, :desc)
  end

  defp comparison_groups(invocations, by) do
    invocations
    |> Enum.group_by(&cost_group_value(&1, by))
    |> Enum.map(fn {name, group} ->
      total_cost = sum_invocation_field(group, :estimated_cost_cents)
      total_tokens = total_tokens(group)
      invocation_count = length(group)

      %{
        name: name,
        invocations: invocation_count,
        sessions: group |> Enum.map(& &1.session_id) |> Enum.uniq() |> length(),
        estimated_cost_cents: total_cost,
        input_tokens: sum_invocation_field(group, :input_tokens),
        cached_input_tokens: sum_invocation_field(group, :cached_input_tokens),
        output_tokens: sum_invocation_field(group, :output_tokens),
        total_tokens: total_tokens,
        cost_per_call_cents: ratio(total_cost, invocation_count),
        tokens_per_call: ratio(total_tokens, invocation_count),
        decisions: frequencies(group, &(&1.decision || "unknown"))
      }
    end)
    |> Enum.sort_by(&{&1.estimated_cost_cents, &1.invocations}, :desc)
  end

  defp cost_group_value(invocation, "model"), do: invocation.model || "unknown"
  defp cost_group_value(invocation, "tool"), do: invocation.tool || "unknown"
  defp cost_group_value(invocation, "source"), do: invocation.source || "unknown"
  defp cost_group_value(invocation, "provider"), do: invocation.provider || "unknown"

  defp sum_invocation_field(invocations, field) do
    Enum.reduce(invocations, 0, &((Map.get(&1, field) || 0) + &2))
  end

  defp total_tokens(invocations) do
    sum_invocation_field(invocations, :input_tokens) +
      sum_invocation_field(invocations, :cached_input_tokens) +
      sum_invocation_field(invocations, :output_tokens)
  end

  defp ratio(_numerator, 0), do: 0.0
  defp ratio(numerator, denominator), do: Float.round(numerator / denominator, 2)

  defp cost_recommendations(%{invocations: 0}, _groups, _by),
    do: ["No invocation cost data has been recorded yet."]

  defp cost_recommendations(totals, groups, by) do
    top_group = List.first(groups)

    []
    |> maybe_reason(
      totals.cached_input_tokens == 0 and totals.input_tokens > 0,
      "No cached input tokens recorded; check whether repeated context can be reused."
    )
    |> maybe_top_cost_reason(top_group, totals, by)
    |> maybe_reason(
      totals.estimated_cost_cents > 0 and totals.invocations > 0,
      "Track cost per successful task once outcomes are available for these invocations."
    )
    |> case do
      [] -> ["Invocation cost distribution looks balanced."]
      recommendations -> recommendations
    end
  end

  defp comparison_recommendations([], _by),
    do: ["No invocation data is available for comparison yet."]

  defp comparison_recommendations(groups, by) do
    top_cost = List.first(groups)
    lowest_cost = Enum.min_by(groups, & &1.cost_per_call_cents, fn -> nil end)

    []
    |> maybe_reason(
      length(groups) > 1 and top_cost != nil,
      "Compare #{by} #{top_cost.name} against lower-cost groups before scaling similar work."
    )
    |> maybe_reason(
      lowest_cost != nil,
      "Lowest observed cost per call is #{lowest_cost.cost_per_call_cents} cent(s) for #{by} #{lowest_cost.name}."
    )
  end

  defp maybe_top_cost_reason(recommendations, nil, _totals, _by), do: recommendations

  defp maybe_top_cost_reason(recommendations, top_group, totals, by) do
    maybe_reason(
      recommendations,
      top_group.estimated_cost_cents > div(totals.estimated_cost_cents, 2),
      "Most estimated spend is concentrated in #{by} #{top_group.name}; compare it against cheaper alternatives before scaling similar runs."
    )
  end

  defp benchmark_draft_records(opts, limit) do
    BenchmarkDraft
    |> maybe_filter_draft_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_draft_status(Keyword.get(opts, :status))
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp benchmark_draft_count(opts) do
    BenchmarkDraft
    |> maybe_filter_draft_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_draft_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_draft_workspace(query, nil), do: query

  defp maybe_filter_draft_workspace(query, workspace_id),
    do: where(query, [d], d.workspace_id == ^workspace_id)

  defp maybe_filter_draft_status(query, nil), do: query
  defp maybe_filter_draft_status(query, status), do: where(query, [d], d.status == ^status)

  defp generate_benchmark_draft(%EvalCandidate{} = candidate) do
    case Repo.get_by(BenchmarkDraft, eval_candidate_id: candidate.id) do
      %BenchmarkDraft{} = existing ->
        {:existing, existing}

      nil ->
        %BenchmarkDraft{}
        |> BenchmarkDraft.changeset(benchmark_draft_attrs(candidate))
        |> Repo.insert()
        |> case do
          {:ok, draft} ->
            {:stored, draft}

          {:error, changeset} ->
            raise "failed to save benchmark draft: #{inspect(changeset.errors)}"
        end
    end
  end

  defp benchmark_draft_attrs(%EvalCandidate{} = candidate) do
    suite_slug = benchmark_suite_slug(candidate)

    %{
      title: "Benchmark draft for #{candidate.rule_id}",
      suite_slug: suite_slug,
      scenario_prompt: benchmark_scenario_prompt(candidate),
      expected_behavior: benchmark_expected_behavior(candidate),
      evidence_summary: candidate.evidence_summary,
      benchmark_hint: candidate.benchmark_hint,
      status: "draft",
      human_gate_required: true,
      workspace_id: candidate.workspace_id,
      eval_candidate_id: candidate.id,
      metadata: %{
        "candidate_rule_id" => candidate.rule_id,
        "candidate_priority" => candidate.priority,
        "candidate_status" => candidate.status,
        "candidate_source_problem_key" => candidate.source_problem_key,
        "example_session_id" => candidate.session_id,
        "example_finding_id" => candidate.finding_id,
        "suggested_action" => candidate.suggested_action
      }
    }
  end

  defp benchmark_suite_slug(%EvalCandidate{benchmark_hint: hint})
       when is_binary(hint) and hint != "" do
    hint
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> then(&if(&1 == "", do: "observability-regression", else: &1))
  end

  defp benchmark_suite_slug(%EvalCandidate{category: category})
       when is_binary(category) and category != "" do
    "#{category}-regression"
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
  end

  defp benchmark_suite_slug(_candidate), do: "observability-regression"

  defp benchmark_scenario_prompt(candidate) do
    "Reproduce the governed failure pattern for #{candidate.rule_id} using summary-only evidence: #{candidate.evidence_summary || "No evidence summary recorded."}"
  end

  defp benchmark_expected_behavior(candidate) do
    "A governed agent should detect or prevent #{candidate.rule_id}, preserve human approval gates, and avoid regressions before promotion. Suggested action: #{candidate.suggested_action || "review candidate evidence"}."
  end

  defp benchmark_draft_summary(%BenchmarkDraft{} = draft) do
    %{
      id: draft.id,
      title: draft.title,
      suite_slug: draft.suite_slug,
      scenario_prompt: draft.scenario_prompt,
      expected_behavior: draft.expected_behavior,
      evidence_summary: draft.evidence_summary,
      benchmark_hint: draft.benchmark_hint,
      status: draft.status,
      human_gate_required: draft.human_gate_required,
      workspace_id: draft.workspace_id,
      eval_candidate_id: draft.eval_candidate_id,
      metadata: draft.metadata || %{},
      inserted_at: format_datetime(draft.inserted_at)
    }
  end

  defp benchmark_draft_recommendations([]),
    do: [
      "No benchmark drafts yet; generate drafts from saved eval candidates before running benchmark coverage."
    ]

  defp benchmark_draft_recommendations(drafts) do
    draft_count = Enum.count(drafts, &(&1.status == "draft"))

    []
    |> maybe_reason(
      draft_count > 0,
      "Review #{draft_count} draft benchmark scenario(s) with a human gate before execution."
    )
    |> maybe_reason(
      Enum.any?(drafts, & &1.human_gate_required),
      "Keep benchmark drafts human-gated until scenario expectations are approved."
    )
    |> case do
      [] -> ["Benchmark drafts are triaged."]
      recommendations -> recommendations
    end
  end

  defp saved_eval_candidate_records(opts, limit) do
    EvalCandidate
    |> maybe_filter_eval_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_eval_status(Keyword.get(opts, :status))
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp saved_eval_candidate_count(opts) do
    EvalCandidate
    |> maybe_filter_eval_workspace(Keyword.get(opts, :workspace_id))
    |> maybe_filter_eval_status(Keyword.get(opts, :status))
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_filter_eval_workspace(query, nil), do: query

  defp maybe_filter_eval_workspace(query, workspace_id),
    do: where(query, [c], c.workspace_id == ^workspace_id)

  defp maybe_filter_eval_status(query, nil), do: query
  defp maybe_filter_eval_status(query, status), do: where(query, [c], c.status == ^status)

  defp save_eval_candidate(candidate, workspace_id) do
    source_problem_key = eval_candidate_source_key(candidate)

    case Repo.get_by(EvalCandidate,
           workspace_id: workspace_id,
           source_problem_key: source_problem_key
         ) do
      %EvalCandidate{} = existing ->
        {:existing, existing}

      nil ->
        %EvalCandidate{}
        |> EvalCandidate.changeset(
          eval_candidate_attrs(candidate, workspace_id, source_problem_key)
        )
        |> Repo.insert()
        |> case do
          {:ok, record} ->
            {:stored, record}

          {:error, changeset} ->
            raise "failed to save eval candidate: #{inspect(changeset.errors)}"
        end
    end
  end

  defp eval_candidate_attrs(candidate, workspace_id, source_problem_key) do
    %{
      title: candidate.title,
      rule_id: candidate.rule_id,
      category: candidate.category,
      severity: candidate.severity,
      priority: candidate.priority,
      evidence_kind: candidate.evidence_kind,
      evidence_summary: candidate.evidence_summary,
      suggested_action: candidate.suggested_action,
      benchmark_hint: candidate.benchmark_hint,
      source_problem_key: source_problem_key,
      status: "open",
      human_gate_required: true,
      workspace_id: workspace_id,
      session_id: candidate.example_session_id,
      finding_id: candidate.example_finding_id,
      metadata: %{
        "affected_session_count" => candidate.affected_session_count,
        "finding_count" => candidate.finding_count,
        "derived_id" => candidate.id,
        "links" => candidate.links
      }
    }
  end

  defp eval_candidate_source_key(candidate) do
    [candidate.rule_id, candidate.category, candidate.severity]
    |> Enum.map(&to_string(&1 || "unknown"))
    |> Enum.join(":")
  end

  defp saved_eval_candidate_summary(%EvalCandidate{} = candidate) do
    %{
      id: candidate.id,
      title: candidate.title,
      rule_id: candidate.rule_id,
      category: candidate.category,
      severity: candidate.severity,
      priority: candidate.priority,
      evidence_kind: candidate.evidence_kind,
      evidence_summary: candidate.evidence_summary,
      suggested_action: candidate.suggested_action,
      benchmark_hint: candidate.benchmark_hint,
      source_problem_key: candidate.source_problem_key,
      status: candidate.status,
      human_gate_required: candidate.human_gate_required,
      workspace_id: candidate.workspace_id,
      session_id: candidate.session_id,
      finding_id: candidate.finding_id,
      metadata: candidate.metadata || %{},
      inserted_at: format_datetime(candidate.inserted_at)
    }
  end

  defp saved_eval_candidate_recommendations([]),
    do: [
      "No saved eval candidates yet; save advisory candidates before generating benchmark coverage."
    ]

  defp saved_eval_candidate_recommendations(candidates) do
    open = Enum.count(candidates, &(&1.status == "open"))
    high = Enum.count(candidates, &(&1.priority in ["critical", "high"]))

    []
    |> maybe_reason(
      open > 0,
      "Review #{open} open saved eval candidate(s) with a human gate before benchmark generation."
    )
    |> maybe_reason(
      high > 0,
      "Prioritize #{high} critical/high saved candidate(s) for regression coverage."
    )
    |> case do
      [] -> ["Saved eval candidates are triaged."]
      recommendations -> recommendations
    end
  end

  defp add_health_actions(actions, overview) do
    actions
    |> maybe_action(
      overview.health.status == "red",
      %{
        id: "health-red-runs",
        title: "Prioritize red session runs",
        category: "health",
        priority: "critical",
        source: "workspace",
        evidence:
          "#{overview.health.red_runs} red run(s), #{overview.problems.total_findings} active finding(s).",
        suggested_action: "Open affected runs and clear blocked findings or review gates.",
        link: "/observability",
        human_gate_required: true
      }
    )
    |> maybe_action(
      overview.health.status == "yellow",
      %{
        id: "health-yellow-runs",
        title: "Review yellow session runs",
        category: "health",
        priority: "medium",
        source: "workspace",
        evidence:
          "#{overview.health.yellow_runs} yellow run(s), #{overview.health.green_runs} green run(s).",
        suggested_action: "Inspect active findings, pending gates, and proof coverage.",
        link: "/observability",
        human_gate_required: true
      }
    )
    |> maybe_action(
      Enum.any?(overview.runs.recent, &(&1.proof_bundles == 0)),
      %{
        id: "proof-coverage",
        title: "Add proof coverage for runs",
        category: "proof",
        priority: "medium",
        source: "session_runs",
        evidence: "At least one recent run has no proof bundle.",
        suggested_action: "Generate proof bundles for runs that need reproducible evidence.",
        link: "/proofs",
        human_gate_required: false
      }
    )
  end

  defp add_problem_actions(actions, problems) do
    Enum.reduce(problems.problems, actions, fn problem, acc ->
      feedback = problem.feedback_loop

      acc ++
        [
          %{
            id: "problem-#{problem.rule_id}",
            title: feedback.eval_candidate_title,
            category: "problem",
            priority: recommendation_priority(problem.health, problem.severity),
            source: "problem_group",
            evidence: feedback.evidence_summary,
            suggested_action: feedback.suggested_action,
            benchmark_hint: feedback.benchmark_hint,
            link: "/observability/problems",
            example_session_id: feedback.example_session_id,
            example_finding_id: feedback.example_finding_id,
            human_gate_required: feedback.human_gate_required
          }
        ]
    end)
  end

  defp add_cost_actions(actions, costs) do
    Enum.reduce(costs.recommendations, actions, fn recommendation, acc ->
      acc ++
        [
          %{
            id: "cost-#{length(acc)}",
            title: "Review cost efficiency",
            category: "cost",
            priority: "low",
            source: "invocations",
            evidence:
              "#{costs.totals.invocations} invocation(s), #{costs.totals.estimated_cost_cents} estimated cent(s).",
            suggested_action: recommendation,
            link: "/observability/costs",
            human_gate_required: false
          }
        ]
    end)
  end

  defp maybe_action(actions, true, action), do: actions ++ [action]
  defp maybe_action(actions, false, _action), do: actions

  defp recommendation_priority("red", _severity), do: "critical"
  defp recommendation_priority(_health, "critical"), do: "critical"
  defp recommendation_priority(_health, "high"), do: "high"
  defp recommendation_priority(_health, _severity), do: "medium"

  defp priority_rank("critical"), do: 1
  defp priority_rank("high"), do: 2
  defp priority_rank("medium"), do: 3
  defp priority_rank("low"), do: 4
  defp priority_rank(_priority), do: 5

  defp recommendation_health(actions) do
    cond do
      Enum.any?(actions, &(&1.priority == "critical")) -> "red"
      Enum.any?(actions, &(&1.priority in ["high", "medium"])) -> "yellow"
      actions == [] -> "green"
      true -> "green"
    end
  end

  defp eval_candidate_from_problem(problem) do
    feedback = problem.feedback_loop

    %{
      id: "eval-#{problem.rule_id}",
      title: feedback.eval_candidate_title,
      rule_id: problem.rule_id,
      category: problem.category,
      severity: problem.severity,
      priority: recommendation_priority(problem.health, problem.severity),
      evidence_kind: feedback.evidence_kind,
      evidence_summary: feedback.evidence_summary,
      suggested_action: feedback.suggested_action,
      benchmark_hint: feedback.benchmark_hint,
      affected_session_count: problem.affected_session_count,
      finding_count: problem.count,
      example_session_id: feedback.example_session_id,
      example_finding_id: feedback.example_finding_id,
      human_gate_required: feedback.human_gate_required,
      links: %{
        problems: "/observability/problems",
        benchmarks: "/benchmarks",
        example_session:
          feedback.example_session_id && "/observability/sessions/#{feedback.example_session_id}"
      }
    }
  end

  defp eval_candidates_health([]), do: "green"

  defp eval_candidates_health(candidates) do
    cond do
      Enum.any?(candidates, &(&1.priority == "critical")) -> "red"
      Enum.any?(candidates, &(&1.priority in ["high", "medium"])) -> "yellow"
      true -> "green"
    end
  end

  defp eval_candidate_recommendations([]),
    do: ["No eval candidates are active from grouped problems."]

  defp eval_candidate_recommendations(candidates) do
    [
      "Review #{length(candidates)} candidate(s) and approve benchmark coverage before promotion.",
      "Start with critical and high priority candidates linked to blocked or recurring findings."
    ]
  end

  defp timeline_event(event) do
    %{
      id: event_value(event, :id),
      event_type: event_value(event, :event_type) || "event",
      actor: event_value(event, :actor) || "unknown",
      summary: event_value(event, :summary) || "No summary",
      body: event_value(event, :body),
      task_id: event_value(event, :task_id),
      inserted_at: format_datetime(event_value(event, :inserted_at))
    }
  end

  defp memory_records(session_id, limit) do
    MemoryRecord
    |> where([r], r.session_id == ^session_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp memory_record_summary(record) do
    %{
      id: record.id,
      record_type: record.record_type,
      title: record.title,
      summary: record.summary,
      tags: record.tags || [],
      source_type: record.source_type,
      source_id: record.source_id,
      archived: not is_nil(record.archived_at),
      inserted_at: format_datetime(record.inserted_at),
      archived_at: format_datetime(record.archived_at)
    }
  end

  defp memory_context_recommendations([], _archived_records),
    do: ["No active memory records are available for this session."]

  defp memory_context_recommendations(_active_records, archived_records) do
    []
    |> maybe_reason(
      archived_records != [],
      "Archived memory is present; confirm current context is not relying on stale notes."
    )
    |> case do
      [] -> ["Session memory has active records available for continuity."]
      recommendations -> recommendations
    end
  end

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
