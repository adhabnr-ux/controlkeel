# Local Observability Feedback Loop

ControlKeel's observability loop is local-first and human-gated. It helps operators convert governed findings into regression evidence without automatically changing policy, router, prompt, or autofix artifacts.

## Workflow

## Evals and observability are one loop

A practical eval platform becomes a flywheel:

1. observe real production traces (what users actually do)
2. cluster failures and weirdness into a small number of recurring patterns
3. promote those patterns into offline eval candidates and benchmark scenarios
4. ship changes behind validation/proof gates
5. keep monitoring production to ensure the change helped and did not regress

CK's observability loop is designed around that same idea: it is not only "logs" and it is not only "offline eval". It is the bridge that turns production evidence into governed regression protection.

1. Inspect current observability posture:

   ```bash
   controlkeel obs status
   controlkeel obs problems
   controlkeel obs recommend
   ```

2. Save advisory eval candidates derived from grouped problems:

   ```bash
   controlkeel obs evals
   controlkeel obs evals save
   controlkeel obs evals persisted
   ```

3. Generate and review local benchmark drafts:

   ```bash
   controlkeel obs benchmarks draft
   controlkeel obs benchmarks drafts
   controlkeel obs benchmarks approve <draft-id>
   # or: controlkeel obs benchmarks reject <draft-id>
   # or: controlkeel obs benchmarks archive <draft-id>
   ```

4. Materialize approved drafts into local benchmark suites and scenarios:

   ```bash
   controlkeel obs benchmarks materialize
   controlkeel obs benchmarks scenarios
   ```

5. Preview and explicitly run generated scenarios from the CLI:

   ```bash
   controlkeel obs benchmarks run --dry-run --subjects controlkeel_validate
   controlkeel obs benchmarks run --execute --suite <observability-suite> --subjects controlkeel_validate
   ```

6. Inspect evidence and advisory promotion readiness:

   ```bash
   controlkeel obs benchmarks history
   controlkeel obs regressions
   controlkeel obs promotions
   ```




## Production signal monitoring

Offline evals and golden datasets are necessary, but they are not enough for long-running production agents. Agents can see unbounded inputs, call tools in unexpected orders, use memory and subagents, and fail silently without a traditional exception. CK should therefore treat production signals as first-class observability evidence.

Useful signal families include:

- **Explicit signals**: tool error rate, validation failures, retry/regeneration rate, latency, token usage, cost, timeout rate, and queue depth.
- **Implicit signals**: refusals, task failure, user frustration, capability gaps, jailbreak or content-moderation risk, lazy/incomplete answers, and positive wins.
- **Trajectory signals**: repeated tool failures, loops, unexpected bypasses, self-correction patterns, and unusual tool-call topology.

Prefer cheap, narrow signals where they are reliable. Regex or keyword heuristics can be useful for aggregate frustration spikes, and small issue-specific classifiers can be cheaper than running an LLM judge over every output. Use LLM judges for sampled or high-value semantic checks rather than as the default monitor for all production traffic.

Signal spikes should feed CK artifacts: findings, trace packets, failure clusters, eval candidates, benchmark drafts, or review packets. They should not directly mutate prompts, tools, policies, or router behavior.

### Trace UX for cross-functional debugging

A usable trace UI is part of the observability loop, not a luxury. It should let engineering, product, data, and CX teams answer "what just happened?" without raw log spelunking:

- show a tool-call timeline with inputs/outputs, errors, retries, and decision checkpoints
- expose cost, latency, and token usage per step so regressions are visible immediately
- filter by cohort, experiment, feature flag, model, prompt, or tool version
- link each trace to the derived finding, failure cluster, eval candidate, or benchmark row
- keep raw payloads redacted and treat the UI as evidence, not authority

The point of the UI is not to centralize everything; it is to make the evidence legible enough that the next iteration is grounded in what actually happened.

### Self-diagnostics as evidence

A self-diagnostic `report` tool — a custom MCP tool you add to your agent's tool list — can let an agent surface repeated tool failures, missing capabilities, user frustration, or unusual self-correction behavior. This is a design pattern for your agent, not a built-in CK feature. Treat these reports as useful evidence from the agent, not as authoritative truth.

Safe self-diagnostic design:

- use neutral framing such as “report notable behavior to maintainers” rather than asking the model to incriminate itself
- classify reports by capability gap, repeated tool failure, user frustration, policy pressure, or self-correction/bypass behavior
- keep reports short, redacted, and linked to trace/proof identifiers
- compare report rates across versions and experiments
- require human/CK review before converting a report into a prompt, tool, or policy change

Self-correction is ambiguous: it can help an agent finish a task, but it can also reveal permission drift or guardrail bypass. CK should record enough trace context to decide which case occurred.

## Minding the observability gap

A useful way to frame agent observability is the gap between **requirements** and **observed behavior**. That gap changes over time as models, prompts, tools, data, users, and operating conditions change. CK should make that drift visible early instead of waiting for production incidents.

Use the loop as a standing lifecycle, not a one-time launch checklist:

- **Evaluate** during build and before every meaningful model, prompt, tool, policy, or harness change.
- **Monitor** live and imported evidence for drift, cost changes, safety signals, and recurring task failures.
- **Optimize** only from reviewed evidence, then rerun the same evals to compare quality, safety, and cost before promotion.

Trace-linked evaluations shorten the detect-to-diagnose path. A score alone says something changed; a score attached to the exact trace, tool call, model response, review, and cost evidence helps explain why it changed.

### Agentic eval checkpoints

For agent workflows, avoid evaluating only the final answer. Split the trace into checkpoints so failures are localizable:

- **Intent resolution**: did the agent understand what the user was trying to accomplish?
- **Tool selection**: did it choose the expected tool, subagent, retrieval path, or refusal/pushback behavior?
- **Tool result handling**: did it ground the next step in the returned evidence rather than inventing missing facts?
- **Task adherence**: did the whole run complete the bounded task without wandering into unrelated work?
- **Final response**: was the answer useful, grounded, safe, and appropriately scoped?

This is especially important for multi-agent or workflow-agent systems. Fleet and workflow traces should let operators compare which subagent, tool, model, prompt version, or policy gate caused the regression without copying raw sensitive payloads into every downstream record.

### Trace metadata boundaries

Custom trace attributes are useful when they make diagnosis faster, but they must stay governed metadata:

- prefer identifiers, versions, counts, hashes, durations, and coarse labels over raw prompts or secrets
- include model, prompt, tool, policy, evaluator, and rubric versions when they affect behavior
- record integrity/provenance for imported trace snapshots
- keep raw payloads in redacted proof artifacts or local trace viewers when possible

CK can interoperate with OpenTelemetry-shaped evidence at the boundary, but CK should not require a particular cloud control plane. The durable CK record is the redacted finding, review, proof, eval candidate, benchmark result, and promotion decision.

## Trace-first eval design

The Arize/Phoenix-style eval workflow reinforces a core CK posture: evals should start from traces, not from guesses about what might fail.

Use this order when turning agent behavior into CK evals:

1. Read representative traces and spans first.
2. Categorize visible failures and near-misses by root cause.
3. Choose the smallest eval that measures the specific failure dimension.
4. Promote recurring failures into benchmark candidates or regression checks.
5. Keep production monitoring active for drift, adversarial inputs, and model-quality changes.

In CK terms, a trace is evidence, not authority. Production traces, local snapshots, debriefs, review comments, and imported envelopes can all seed `obs problems`, failure clusters, eval candidates, and benchmark drafts. They should not directly rewrite policy, router, prompt, or skill artifacts.

Prefer production traces when they exist because they reflect real user behavior. Use synthetic data only to fill gaps, cover rare safety cases, or bootstrap a new workflow before production evidence is available.

## Choosing the right eval shape

Different failures need different evals:

- Use deterministic code evals for objective checks: exact labels, schema conformance, known policy violations, required citations, expected files, or blocked capabilities.
- Use LLM-as-judge only for semantic dimensions that deterministic checks cannot cover, such as answer usefulness, groundedness, or tone.
- Use human review to create or audit golden data, not as the only scalable production gate.
- Split broad quality questions into narrow dimensions. Avoid one "god evaluator" that tries to score correctness, faithfulness, safety, tone, and completeness at once.

For judge-based evals, require a narrow rubric, anchors, constrained output labels, and meta-evaluation against human or golden labels before treating the judge as decision-useful. If the evaluator cannot distinguish the failure mode in historical traces, it should not gate promotion.

Agent workflows should be evaluated by outcome and safety properties, not by requiring one exact trajectory. Agents may solve a task through unexpected but acceptable paths; CK should care whether the bounded slice was completed, evidence remained reviewable, and governance constraints held.

## Safety boundaries

- `obs evals save` stores local advisory eval candidate records only.
- `obs benchmarks draft` creates local draft scenarios only.
- `obs benchmarks approve|reject|archive` changes only local draft review state.
- `obs benchmarks materialize` creates local `Benchmark.Suite` and `Benchmark.Scenario` records; it does not run benchmarks.
- `obs benchmarks run --dry-run` is non-mutating preview.
- `obs benchmarks run --execute` is the only observability command in this loop that records benchmark execution, and it delegates to the existing local benchmark runner.
- `obs promotions` is advisory reporting only and returns promotion candidates with no policy, router, prompt, or autofix mutation.

## Local telemetry snapshots

Use local envelopes when you need to move or inspect observability evidence without mutating live sessions:

```bash
controlkeel obs export <session-id>
controlkeel obs import <file> --dry-run
controlkeel obs import <file> --persist
controlkeel obs imports
```

Persisted imports are snapshots and are deduplicated by payload hash; they do not rewrite sessions, findings, or memory.

## Optional Raindrop Workshop evidence

Raindrop Workshop is a local-first trace viewer with a local daemon and UI for runs, spans, and live events. CK should treat Workshop as an **optional evidence source**, not as a required runtime or an authority surface. The useful boundary is:

- Workshop: low-latency local trace viewing.
- ControlKeel: governed summaries, redaction, findings, eval candidates, benchmark evidence, and human-gated promotion.

Use `controlkeel obs workshop <snapshot.json> --dry-run` to preview a local Workshop-shaped snapshot. The preview is summary-only: raw span payloads and event content remain in Workshop or separate proof artifacts. This lets teams decide whether a trace contains useful CK eval/benchmark evidence before persisting anything.

Build-vs-integrate stance: CK should build the durable governance loop itself and integrate with Workshop only at the evidence boundary. That keeps CK portable across hosts while still benefiting from Workshop's local trace UI when operators choose to run it.

## Event-sourced harness lessons

The event-sourced agent-harness pattern is a good fit for CK when it is applied as a governance discipline rather than as an unbounded execution substrate:

- Keep the raw trajectory append-only: user inputs, model deltas, tool calls, validation results, reviews, and operator interventions should be durable facts.
- Derive state through projections: dashboards, loop status, failure clusters, benchmark candidates, and readiness summaries should be rebuildable from recorded evidence.
- Separate projections from effects: reducers should summarize state; side-effect processors should be explicit, rate-limited, and reviewable.
- Prefer after-append processors over before hooks: before hooks can silently perturb context, break caching, or add latency; CK should model checks as visible events and bounded gates.
- Treat loop prevention as product behavior: idempotency keys, event-rate circuit breakers, pause/resume events, and budget limits are required for distributed agent work.
- Treat processor code as supply-chain input: dynamic workers, generated plugins, skills, or prompt patches need provenance and human/CK review before they affect execution.

This maps to the existing CK loop: trace packets and imported snapshots feed `obs problems`, failure clusters, eval candidates, and benchmark drafts. They do not directly mutate policies, router behavior, prompts, or skills.

## Trace reality check

Phil from BrainTrust emphasizes that agent traces are fundamentally different from normal application traces. They are "nasty" - semi-structured, unstructured, and massive. Traditional spans might be a couple kilobytes, but agent spans can be 10-20 megabytes because they contain so much context.

This creates a systems problem:
- **High velocity**: Lots of usage in production
- **Large payloads**: 10-20MB spans vs 2KB traditional spans
- **Highly unstructured**: Just so much text inherent to LLM problems
- **Two query patterns**: Low latency for instant trace viewing, plus aggregate analytics for understanding behavior
- **Full-text search expectations**: Users want to search across millions of traces

CK's stance is not "just store it in a spreadsheet". Use the local observability and benchmark workflow to keep the evidence portable, reviewable, and promotable into regression protection.


## Opt-in telemetry sync levels

When teams need shared observability across multiple ControlKeel instances, telemetry sync becomes valuable. The opt-in levels are cumulative and strictly increasing:

| Level | What syncs | When to use |
| --- | --- | --- |
| **Health** | Heartbeat, version, workspace ID | Fleet monitoring; no governance content |
| **Governance metadata** | Finding counts, review status, budget summaries | Team dashboards; no source code or diffs |
| **Evidence sync** | Proof bundles, review packets, memory citations (redacted) | Cross-host coordination; shared audit trail |
| **Full enterprise audit** | Complete session transcripts (redacted), benchmark results, policy change history | Regulated environments; SOC 2 / GDPR compliance audit |

Key boundaries:

- Telemetry sync is off by default. Operators must explicitly enable it per-workspace.
- The local observability loop works fully without any telemetry sync. Local evidence, benchmarks, eval candidates, and promotion candidates remain the primary surfaces.
- Sync applies the same redaction rules as proof bundles and audit exports before data leaves the node.
- There is no automatic escalation between levels.

The phased build path for these sync levels is documented in [cloud-enterprise-roadmap.md](cloud-enterprise-roadmap.md).

## Learning loop status

Use `controlkeel obs loop` or the read-only MCP `ck_observability` report `loop_status` when an agent or operator needs the whole self-improvement picture in one place. The loop status combines active problems, derived and saved eval candidates, benchmark drafts, materialized scenarios, benchmark history, promotion readiness, blockers, and next actions.

This report is intentionally evidence-driven and human-gated: generated benchmarks are regression seeds for operator review, benchmark execution stays explicit, and policy/router/prompt/skill promotion is never automatic. Agents should use the report to propose safer next steps, not to mutate artifacts directly.

## Unknown-unknowns and topic modeling

Phil emphasizes that eval platforms should tell users about the "unknown unknowns" - don't make users look across a whole bunch of traces to understand how people are using their agent. Instead, use topic modeling techniques to automatically uncover usage patterns so teams know where to spend their engineering time.

This aligns with CK's `obs problems` and `ck_failure_clusters` approach: instead of forcing operators to manually review every trace, cluster failures and weirdness into a small number of recurring patterns that become eval candidates.

## Headless and agent-facing platforms

A growing trend is building platforms not just for humans but also for agents. Phil notes that many use cases are "headless" - users aren't interested in the UI at all, only in how they can use a coding agent (like Claude Code or Cloud Code) to grab data from the evals platform in aggregate and improve their agents.

CK's MCP interface and local-first design support this pattern:
- `ck_observability` provides structured data that agents can consume
- Local benchmark workflows can be automated by agents
- The focus is on portable evidence that can be moved between systems, not just human-readable dashboards

## Role-based access control and data masking

When operating at scale, especially with production traces that may contain sensitive data, role-based access control and data masking become critical. Phil notes these as important non-functional requirements for eval platforms.

CK's governance layer already supports this through:
- Workspace and session scoping
- Service-account based access control
- Trust-boundary validation that can mask or block sensitive data
- Local-first design that keeps data under operator control

## Automatic tracing

Phil mentions adding automatic tracing through an AI proxy or gateway for centralized governance. This ensures people don't have a choice but to trace their LLMs, enabling very centralized governance.

CK's provider broker and proxy controller already implement this pattern for model APIs, and the same approach can be extended to MCP and other agent protocols.

## Factory-oriented framing

When teams talk about a "software factory", they are usually describing an environment where:

- work runs asynchronously across many agents
- humans review outcomes more than they read every line
- failures are caught by guardrails, tests, and observability
- repeated mistakes are turned into durable guidance

In CK terms, the observability loop is the "control panel" for that factory:

- use `ck_observability` (`loop_status`) to see whether agents are making progress or circling
- use `ck_failure_clusters` to group recurring failure modes into concrete eval candidates
- use `ck_skill_evolution` to draft updated Do/Avoid/Verification guidance from real traces

The intent is to make continual learning **explicit and reviewable** rather than implicit provider memory.

### Post-run debriefs as a low-cost signal

A simple, cheap way to find harness and instruction failures is to debrief the agent at the end of a run (such as via a host stop-hook):

- "What blocked you or confused you in this run?"
- "What single change to the instructions/tools would have made you more successful?"

In CK terms, those answers should be treated as **observability inputs**:
- recurring debrief failures belong in `obs problems`
- clustered patterns become eval candidates (`ck_failure_clusters`)
- human-reviewed improvements become skill evolution drafts (`ck_skill_evolution`)

### "Garbage collection" loop (turn review pain into guardrails)

A scalable harness improvement loop is to treat recurring PR review feedback as observability data:

- collect the top recurring "slop" comments humans and reviewer agents leave
- classify them by persona (reliability, security, frontend architecture, API design)
- convert them into durable guardrails (skills/checklists, lints, source-shape tests, reviewer prompts)
- re-run the observability loop to confirm the failure class stopped recurring

In CK terms, this maps cleanly to the existing pipeline:

- repeated review pain becomes `obs problems`
- clusters become eval candidates (`ck_failure_clusters`)
- the resulting guidance becomes reviewed skill drafts (`ck_skill_evolution`)

### Review agent limitations

Review agents can catch some issues, but they have fundamental limitations. As Mario points out, review agents (and models in general) learn complexity from the internet—and 90% of code on the internet is "our old garbage." There are pearls, but the training data is dominated by mediocre patterns.

This means:

- Review agents may suggest patterns that look sophisticated but are actually the same complexity they learned from bad patterns
- They cannot substitute for human judgment on architecture, product fit, or domain-specific constraints
- They compound the same "local decisions, global mess" problem that generator agents have

CK's stance is that review agents are **helpers, not replacements**:

- Use them for mechanical feedback (formatting, missing tests, small refactors)
- Keep humans in the loop for judgment calls (permissions, migrations, auth boundaries, irreversible operations)
- Treat review agent output as advisory, not authoritative

The observability loop helps by tracking which review feedback actually prevents regressions and which is noise—so teams can tune their review processes over time.

Ryan's team operationalized this with "garbage collection day" (Fridays) where engineers took all the slop observed during the week and figured out how to categorically eliminate it. They bucketed review feedback by persona (frontend architect, reliability engineer, scalability) and spun up review agents for each that trigger on every push. With continuous appending to these docs, slop reduced systematically.

The goal is not perfect code. The goal is to systematically delete high-churn review minutiae so humans spend their scarce attention on high-leverage decisions.
