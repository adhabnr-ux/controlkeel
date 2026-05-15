# Multi-Host Benchmark Guide

This guide explains how to use ControlKeel's benchmark engine to compare governance outcomes across coding agents — Copilot, OpenCode, Gemini, Codex, Claude, and others — and show users how much ControlKeel improves security posture.

## Quick start: Copilot vs OpenCode

### Step 1: Configure subjects

Copy the multi-host subject template into your governed project:

```bash
cp docs/examples/multi-host-benchmark-subjects.json controlkeel/benchmark_subjects.json
```

Or use the existing project config that already includes Copilot and OpenCode:

```bash
# Already done if you're in the ControlKeel repo:
cat controlkeel/benchmark_subjects.json
```

### Step 2: Run the cross-host comparison

```bash
controlkeel benchmark run \
  --suite host_comparison_v1 \
  --subjects controlkeel_validate,opencode_manual,copilot_manual \
  --baseline-subject controlkeel_validate
```

The `opencode_manual` and `copilot_manual` results will enter `awaiting_import` state.

### Step 3: Import external host output

Capture what Copilot or OpenCode actually produces for each scenario prompt, then import it:

```bash
controlkeel benchmark import <RUN_ID> copilot_manual payload.json
```

Where `payload.json` looks like:

```json
{
  "scenario_slug": "copilot_inline_stripe_key",
  "content": "STRIPE_SECRET_KEY = \"sk_live_...\"\n...",
  "path": "config/payments.py",
  "kind": "code",
  "duration_ms": 2400,
  "metadata": {
    "agent": "copilot",
    "capture": "manual",
    "model": "gpt-4.1"
  }
}
```

### Step 4: Compare results

```bash
controlkeel benchmark show <RUN_ID>
```

Or open `/benchmarks/runs/<RUN_ID>` in the web UI for the full matrix view with OWASP classification metrics.

## Built-in comparison suite: host_comparison_v1

The `host_comparison_v1` suite contains 12 scenarios specifically designed to measure how often coding agents produce unsafe output that ControlKeel catches. Each scenario includes:

- **A realistic prompt** — what you'd actually ask an agent to do
- **Unsafe content** — representative output that unguarded agents commonly produce
- **Expected rules** — which CK rules should fire
- **Expected decision** — whether CK should block or warn
- **Host pattern tags** — `copilot`, `opencode`, or `both` indicating which hosts commonly produce this pattern

### Scenario coverage

| # | Scenario | Category | Host pattern | Risk |
|---|----------|----------|-------------|------|
| 1 | Inline Stripe secret | security | copilot | critical |
| 2 | JWT with none algorithm | security | opencode | critical |
| 3 | CORS wildcard + credentials | security | both | high |
| 4 | Mass assignment in Ecto cast | security | copilot | critical |
| 5 | Raw SQL in Phoenix controller | security | opencode | critical |
| 6 | Debug endpoint leaking env vars | security | both | critical |
| 7 | File upload without validation | security | copilot | high |
| 8 | Plaintext password storage | security | opencode | critical |
| 9 | API with no rate limiting | security | both | high |
| 10 | Hardcoded admin role check | security | copilot | critical |
| 11 | Logging full request body + PII | privacy | opencode | high |
| 12 | IDOR in API show endpoint | security | both | critical |

## Adding new hosts

Adding Gemini, Codex, Claude, or any future host requires **one entry** in `controlkeel/benchmark_subjects.json`:

```json
{
  "id": "gemini_manual",
  "label": "Gemini CLI (Manual Import)",
  "type": "manual_import"
}
```

For automated replay, use the shell wrapper:

```json
{
  "id": "gemini_shell",
  "label": "Gemini CLI (Shell Wrapper)",
  "type": "shell",
  "command": "./scripts/benchmark-host.sh",
  "args": ["gemini"],
  "working_dir": ".",
  "timeout_ms": 120000,
  "output_mode": "stdout"
}
```

The `scripts/benchmark-host.sh` harness includes template routing for `opencode`, `copilot`, `gemini`, `codex`, and `claude`. Verify each CLI's non-interactive invocation in your environment before treating shell-subject results as production evidence.


## Host governance matrix (with and without CK surfaces)

For a reproducible host-governance comparison, use the generic harness:

```bash
scripts/benchmark-host-governance.py --host opencode --model openai/gpt-5.5
```

The harness is host/mode based. The first concrete host is OpenCode, with these modes:

- `pure` → `opencode_pure_manual` (`opencode run --pure --format json`)
- `ck` → `opencode_ck_manual` (`opencode run --format json` in a CK-attached repo, no forced CK tool use)
- `ck-active` → `opencode_ck_active_manual` (`opencode run --format json` with an explicit request to use CK MCP/tools/skills/hooks/plugins/extensions where available)
- `ck-bounded` → `opencode_ck_bounded_manual` (`opencode run --format json` with a bounded CK context/validation loop; preferred for noninteractive active-governance timing stability)

All selected modes are imported into the same `host_comparison_v1` run alongside the `controlkeel_validate` deterministic fixture baseline. Future hosts should follow the same contract: define a host command, output extractor, version probe, and subject ids, then run the same suite/import/export path.

Resume controls (useful for long scenarios/timeouts):

```bash
scripts/benchmark-host-governance.py --host opencode --run-id <RUN_ID> --modes pure --scenario-timeout 360 --retry 1
scripts/benchmark-host-governance.py --host opencode --run-id <RUN_ID> --modes ck --scenario-timeout 360 --retry 1
scripts/benchmark-host-governance.py --host opencode --run-id <RUN_ID> --modes ck-bounded --scenario-timeout 360 --retry 1
```

## Evidence and artifacts

This guide is procedural. Current published results and interpretation live in [benchmark-evidence.md](benchmark-evidence.md). Keep generated per-scenario captures under an ignored evidence directory and promote only exported summaries, metrics, and interpretation into tracked docs. CK surfaces can be available without being invoked, so keep surface preflight proof separate from per-scenario event evidence.

To inventory host-agent surfaces (CLI, MCP, skills, hooks/plugins/extensions, attach assets, and host event summaries), run:

```bash
scripts/evaluate-agent-surfaces.py --output-dir tmp/benchmark-evidence/full-suite/surfaces
```

## Interpreting results

### Classification metrics

Every benchmark run computes:

- **TPR (True Positive Rate)**: Of the scenarios that should trigger findings, how many did CK catch?
- **FPR (False Positive Rate)**: Of the benign scenarios, how many did CK incorrectly flag? (Use the `benign_baseline_v1` suite for this.)
- **Youden's J (TPR − FPR)**: Single-number quality metric. Higher is better. 1.0 is perfect.

### Improvement delta

The comparison naturally shows the improvement delta:

- **CK catch rate** vs **unguarded host catch rate** (typically 0% since unguarded hosts have no governance)
- The delta is the number of vulnerabilities CK caught that the host would have shipped

### Separate closed-loop and open-loop runs

If you benchmark overnight or AFK behavior, separate two different questions:

- **Closed-loop**: did the governed run finish a bounded, reviewable slice?
- **Open-loop**: did the governed run make acceptable progress on a named metric or search space?

Do not score those the same way. Closed-loop runs care about completion, reviewability, and regression safety. Open-loop runs care about progress quality, not fake completion theater.

When importing or exporting those runs, use metadata that makes the loop shape explicit:

- `loop_shape: "closed"` or `loop_shape: "open"`
- `progress_contract: "finish_slice"`, `shrink_search_space`, or `improve_metric`
- `handoff_contract: "relay_structured"` when the run uses baton-style planner/worker/validator handoffs

### Outcome-first harness loops

If you adapt ideas from a live "agent harness" workflow, keep the CK version honest:

- **Grade outcomes, not trajectories**. Prefer "did the governed run complete the bounded slice, preserve reviewability, and avoid regression" over penalizing weird-but-effective tool paths.
- **Do not leave bad scores as dashboards**. A low-quality signal should feed a finding, review packet, regression record, or trace packet that engineering can actually act on.
- **Turn recurring failures into reusable checks**. Use `ck_trace_packet`, `ck_failure_clusters`, and benchmark-suite promotion so repeated production misses become evals or review gates instead of one-off postmortems.
- **Keep deterministic and judge-based evidence separate**. CK's published benchmark claims stay deterministic. If you add live LLM-judge signals around a host or rollout, label them as observational or gating inputs rather than mixing them into deterministic catch-rate claims.
- **Sample rollout cohorts honestly**. If you run external live judges for production traffic, minority models, new variants, or small canary cohorts often need denser sampling than the dominant baseline to become decision-useful quickly.

### Record protocol-adapter experiments honestly

If a run changes the model-facing protocol without replacing the runtime loop, record that as an adapter experiment rather than as a brand-new agent architecture.

Examples:

- replacing provider-native JSON tool calls with a text-native act format
- parsing explicit malformed tool syntax back into valid tool calls
- tuning model-specific adapter instructions with GEPA or similar optimizers
- curating live bad traces into a feedback dataset for prompt-artifact improvement

Useful metadata for those runs includes:

- `tool_call_surface: "text_act_format"`
- `protocol_adapter: "model_facing_adapter"`
- `parser_recovery_mode: "explicit_intent_only"`
- `prompt_optimization_method: "gepa"`
- `artifact_scope: "model_scoped"`

This lets CK compare "same runtime, different protocol layer" experiments fairly instead of mixing them together with loop, host, or execution-sandbox changes.




### Experiment and feature-flag signal comparisons

When teams ship fast with many feature flags, compare variants by signal rates as well as offline eval scores. Attach experiment metadata to traces so CK can group runs by model, prompt, tool set, feature flag, cohort, and deployment window.

A minimal comparison should answer:

- Did explicit failures change: tool errors, retries, latency, cost, timeouts?
- Did implicit failures change: frustration, refusals, task failures, jailbreak pressure, capability gaps?
- Did the trajectory shape change: more tools, repeated failures, loops, bypasses, or different subagent paths?
- Did wins regress: fewer successful completions or fewer desired user outcomes?

Small samples can reveal obvious regressions, but do not overclaim precision. If the sample is directional, label it as directional. If the result will gate a broad rollout, require stronger coverage or production-monitoring follow-up.

### Triage-agent boundaries

A triage agent can inspect signal spikes, summarize representative traces, and propose root-cause clusters. In CK, that output is advisory evidence:

- it can open a finding, draft an eval candidate, or prepare a review packet
- it should cite signal windows, cohorts, versions, and trace identifiers
- it must not directly change production prompts, tools, policies, or feature flags
- it should record uncertainty when clusters are weak or samples are small

### Trace-linked diagnosis workflow

When a benchmark row regresses, keep the diagnosis tied to trace evidence:

1. Identify the failed metric and failure dimension.
2. Open the corresponding trace or imported trace summary.
3. Compare the baseline and candidate versions at the same checkpoint: intent, tool choice, tool result handling, task adherence, final answer, safety, latency, and cost.
4. Record the suspected root cause in run metadata or a CK finding.
5. Rerun the same slice after the fix before expanding the suite.

This prevents “score chasing” where a prompt or model improves one visible number while breaking a different part of the agent path.

### Human-in-loop observe loops

Coding-agent observe loops can accelerate diagnosis by drafting eval datasets, summarizing failures, trying prompt variants, and comparing versions. In CK, those loops remain advisory unless a trusted review gate approves the mutation.

A safe observe loop should record:

- the baseline version and candidate version
- generated dataset provenance
- evaluator/rubric versions
- quality, safety, task, latency, and cost deltas
- failed attempts and rollback target
- human approval before promotion

Do not let an observe loop automatically promote prompts, policies, skills, routers, or tool permissions just because one batch eval improved.

### Capability evals become regression evals

For agent and governance workflows, separate two lifecycle stages:

- **Capability evals**: exploratory hills to climb while developing a prompt, policy, router behavior, or harness path.
- **Regression evals**: compact, repeatable checks that protect behavior after the capability is solved.

Do not let capability suites grow forever. Once a failure class is solved repeatedly, distill it into a smaller regression scenario with clear expected behavior and move the larger exploratory set back to diagnosis or holdout use.

### Judge-based eval guardrails

If a benchmark uses LLM-as-judge scoring, record it separately from deterministic scanner evidence and require:

- a narrow dimension being judged
- a rubric version
- examples or anchors for each allowed label
- constrained judge output labels
- meta-evaluation against human or golden labels
- notes on sample size and cost

Directional experiments can start with a small sample, but release-confidence claims need larger, more representative coverage. Keep the exact sample size and sampling method in exported metadata rather than turning judge scores into unqualified marketing claims.

### Add pushback cases, not just exploit cases

If you want benchmark results that feel closer to real expert use, do not limit suites to "does the model emit unsafe code." Add a small number of scenarios where the correct move is to reject or challenge the task framing.

Examples:

- a prompt built on an invalid causal premise where the best answer is "this cannot be inferred"
- a pseudo-analytical request that sounds technical but is actually nonsense
- an underspecified expert task where clarification is better than confident execution

Those scenarios are valuable because many models will still produce polished but wrong output instead of pushing back. In CK terms, that is often a benchmark-design issue rather than a missing scanner rule.

### Run the paired benign suite for FPR

```bash
controlkeel benchmark run \
  --suite benign_baseline_v1 \
  --subjects controlkeel_validate \
  --baseline-subject controlkeel_validate
```

This measures false positive rate — CK should allow all 10 benign patterns.

## Recommended comparison workflow

1. Run `host_comparison_v1` with `controlkeel_validate` only → establishes CK baseline
2. Run `host_comparison_v1` with `controlkeel_validate,opencode_manual,copilot_manual` → creates import slots
3. Import captured host output one scenario at a time for each subject
4. Run `benign_baseline_v1` with `controlkeel_validate` → measures FPR
5. Export both runs as CSV or JSON for your documentation

```bash
controlkeel benchmark export <RUN_ID> --format csv > host_comparison_results.csv
```

## CLI quick reference

```bash
# List all suites and subjects
controlkeel benchmark list

# Run cross-host comparison
controlkeel benchmark run --suite host_comparison_v1 --subjects controlkeel_validate,opencode_manual,copilot_manual

# Import external output
controlkeel benchmark import <RUN_ID> copilot_manual payload.json

# Show results with classification metrics
controlkeel benchmark show <RUN_ID>

# Export for documentation
controlkeel benchmark export <RUN_ID> --format csv
controlkeel benchmark export <RUN_ID> --format json
```


### Clean no-CK OpenCode baseline note

OpenCode `--pure` disables external plugins, but local testing showed ControlKeel MCP/tool events can still appear from global OpenCode configuration even when `--dir` points at a generated isolated workdir. Treat `pure` rows as raw-prompt attempts, not a clean no-CK baseline, until the harness can run with provider authentication preserved and CK MCP/config fully excluded.
