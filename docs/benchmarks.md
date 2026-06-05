# ControlKeel Benchmarks

ControlKeel benchmarks test whether a governed change improved a concrete agent workflow. Keep benchmark claims bounded to the suite, subject, scenario count, scorer, and caveats.

## Claim discipline

Good claims:

- "Direct deterministic validation caught 12/12 risky scenarios in `host_comparison_v1`; 9/12 were hard blocks."
- "Bounded active governance used roughly half the tokens of exhaustive active governance on the same suite."
- "This promotion improved held-out catch rate without increasing false blocks on the benign baseline."

Bad claims:

- "CK makes agents safe" without a suite and scoring definition.
- "CK reduces cost by X%" when the run only measured tokens or latency.
- "This model is better" when prompt, tool set, policy, and evaluator changed at the same time.

The bar is reproducibility: baseline, candidate, one changed variable, held-out split, and rollback path.

## Benchmark lifecycle

1. Mine findings, traces, review comments, support reports, and failure clusters.
2. Classify the failure dimension before choosing the scorer.
3. Draft small, behavior-rich scenarios.
4. Keep optimization and held-out splits explicit.
5. Run baseline and candidate against the same suite.
6. Promote only when quality, safety, latency, and cost stay inside the operating envelope.

Use [observability-feedback-loop.md](observability-feedback-loop.md) for the local evidence-to-draft workflow. This file owns scoring and metadata discipline.

## Subject types

- `controlkeel_validate` — direct deterministic validation path.
- `controlkeel_proxy` — governed proxy path.
- `manual_import` — awaiting-import run first, then import captured external output.
- `shell` — scriptable subject that writes stdout or files for rescoring.

The recommended first external comparison is `ControlKeel Validate` vs `OpenCode Manual Import`; it is reproducible without requiring a deeper native integration first.

## Scenario design

Prefer deterministic checks when possible:

- policy, schema, exact-match, capability, and regression assertions
- required citations, expected files, blocked actions, or refusal requirements
- source-shape constraints such as file size, layering, or dependency edges

Use judge-based scoring only for narrow semantic dimensions with rubrics, anchors, constrained labels, and meta-evaluation against human/golden labels.

Keep these eval families separate:

| Family | Use |
| --- | --- |
| Capability eval | Measures a hill the system is trying to climb. |
| Regression eval | Preserves behavior that already works. |
| Red-team eval | Tests hostile inputs, tool misuse, leakage, or prohibited actions. |
| Persona eval | Scores role-specific output expectations without averaging them away. |
| Premise-refusal eval | Checks whether the agent resists bad assumptions or over-solving. |

## Required metadata

Every scenario should carry enough metadata to explain what changed and why the result matters.

Core fields:

- `eval_source`: `production_trace`, `synthetic`, `review_feedback`, `operator_debrief`, or `red_team`
- `eval_mode`: `deterministic`, `llm_judge`, or `human_golden`
- `failure_dimension`: `correctness`, `faithfulness`, `safety`, `schema`, `groundedness`, or `task_completion`
- `domain_pack`, `task_type`, `artifact_type`, `security_workflow_phase`
- `behavior_tags`
- `baseline_run_id`, `candidate_run_id`, `rollback_target_version`

Version fields:

- `model_version`
- `prompt_version`
- `tool_version`
- `workflow_version`
- `policy_version`
- `evaluator_version`
- `rubric_version`

Signal fields for production-derived evals:

- `signal_source`: `explicit`, `implicit`, `trajectory`, or `self_diagnostic`
- `signal_name`
- `signal_rate_baseline`
- `signal_rate_candidate`
- `feature_flag`, `experiment_id`, `cohort_id`
- `representative_trace_ids`

## Specialized metadata

Persona output:

- `persona_role`
- `output_focus`
- `format_profile`
- `tone_profile`

Red-team:

- `attack_strategy`
- `risk_category`
- `allowed_actions`
- `prohibited_actions`
- `safety_gate_version`

Retrieval quality:

- `search_task_type`
- `retrieval_strategy`
- `orientation_metric`
- `result_presentation`
- `memory_surface`

Runtime experiments:

- `runtime_contract`
- `adapter_contract`
- `tool_encoding`
- `execution_surface`
- `experiment_variable`

Skill activation:

- `expected_skill`
- `activation_signal`
- `false_positive_guard`
- `token_snapshot`

Delegation and subagent surfaces:

- agent identity, role, and authority boundary
- handoff packet completeness
- dependency graph and blocking relationships
- async/background status, event logs, progress, interrupt behavior, and completion receipts

## Split discipline

Built-in scenarios can carry split-aware metadata:

- `public` for reusable suites
- `held_out` for reserved evaluation

Do not tune prompts, policies, or router behavior on held-out scenarios. Promote only when held-out evidence improves without backsliding on safety, false-block, latency, or cost constraints.

## Large artifacts

Treat screenshots, videos, audio, binary reports, PR previews, and UI diffs as referenced artifacts:

- store bytes in object storage or file-backed proof bundles
- keep pointers, metadata, and integrity digests in the run record
- render or inspect them in review surfaces when needed

Do not stuff large binaries into database rows or transcripts.

## Rollout abort threshold

Use benchmark results as release gates for behavior-changing harness work. Abort or require human review if:

- held-out catch rate drops
- benign false-block rate rises
- critical red-team scenarios regress
- latency or token cost exceeds the approved envelope
- scenario diversity or classification evidence is missing

For minority or experimental model integrations, route enough traffic to reach decision-useful evidence instead of relying on tiny proportional samples.

## Web UI quick presets

On `/benchmarks`, Quick presets can fill subject and baseline fields for common runs such as OpenCode comparison, ControlKeel validate only, or validate plus governed proxy. The subjects field still accepts a comma-separated list and browser autocomplete from Available subjects.

## Interpretation

Use benchmark results as product evidence, but keep the claim precise:

- name the suite
- name the subjects
- disclose scenario count and split
- distinguish catch rate from block rate
- report latency, token, or cost proxies honestly
- keep false positives visible
- record rollback criteria
