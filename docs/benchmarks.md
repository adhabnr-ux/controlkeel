# ControlKeel Benchmarks

ControlKeel ships a persisted benchmark engine for comparing governed subjects and external agents against the same scenario suites.

CK’s benchmark model is meant to support the same harness-improvement loop people now use for agent evals:

- mine production traces and failure clusters for candidate evals
- curate small, behavior-rich suites instead of blindly growing noisy corpora
- keep explicit split boundaries so optimization work does not quietly overfit
- use benchmark exports as the durable evidence surface for harness changes

That also makes it the right outer loop for GEPA-style optimization work:

- use CK scenarios and split discipline as the scored signal
- let GEPA-style search mutate prompts, text configs, or harness instructions outside CK
- bring the candidate back through CK benchmark and policy-training surfaces
- promote only when the candidate improves held-out evidence, not just the visible optimization split

## Console-first evaluation posture

Evals often start as "a for-loop + a spreadsheet" and then grow into a bespoke UI. That is a useful on-ramp, but production-quality eval and observability becomes a **systems problem**:

- production traces are high-velocity, text-heavy, and not cleanly structured
- teams need both low-latency trace inspection and aggregate analytics
- headless workflows emerge (agents and CI want to query, score, and promote without clicking a UI)

CK's bias is to keep the evidence loop console-first and exportable so the maturity path stays grounded in verifiable artifacts (trace packets, failure clusters, benchmark suites, run exports) rather than only dashboards.

For early agent and harness work, prefer a console-first loop before building product UI around it.

- keep the benchmark, trace packet, and failure-cluster loop close to the real execution surface
- make the harness behavior inspectable before investing in dashboards or orchestration chrome
- treat reproducible benchmark exports, held-out transfer, and regression catches as the evidence, not the prettiness of the interface

This is especially important when trying new prompting schemes, tool-call formats, recursive workflows, or optimizer loops. If the behavior is not legible in a small console-first path, UI polish will usually hide the problem rather than solve it.




## Production signals as eval seeds

Production monitoring should feed benchmark design when signals show recurring or high-impact failure modes. A signal is not automatically a benchmark; first cluster the traces and identify the failure dimension.

Good candidates include:

- rising tool error or timeout rates
- upstream tool or search regressions after provider updates
- repeated retries or regenerations
- per-interaction cost spikes or context bloat
- user frustration spikes
- refusal-rate changes
- capability-gap reports
- jailbreak or content-moderation pressure
- repeated self-correction or bypass patterns
- positive “win” patterns worth preserving

When converting a production signal into an eval, keep both the aggregate metric and representative traces. The benchmark should explain what changed, who was affected, and which version or feature flag was active.

Recommended metadata:

- `signal_source: "explicit"`, `"implicit"`, `"trajectory"`, or `"self_diagnostic"`
- `signal_name`
- `signal_rate_baseline`
- `signal_rate_candidate`
- `feature_flag`
- `experiment_id`
- `cohort_id`
- `trajectory_shape`
- `representative_trace_ids`

This makes production-derived evals auditable and avoids turning one noisy anecdote into a permanent benchmark.

## Persona-specific output benchmarks

For user-facing summaries or copilots, one prompt rarely serves every role. Benchmark suites should tag persona-specific expectations instead of averaging them away.

Suggested metadata:
- `persona_role` (sales, engineering, HR, executive, support)
- `output_focus` (deal risk, action items, blockers, compliance, next steps)
- `format_profile` (bullets, narrative, ticket list, follow-up draft)
- `tone_profile` (concise, executive, technical, empathetic)

Prefer small per-persona eval slices, then compare deltas across personas rather than chasing one global score.

## Regression comparisons after every change

Any change that can alter agent behavior should be treated as an experiment:

- model or deployment version
- prompt/instruction version
- tool set, tool implementation, or retrieval corpus
- router, policy, guardrail, or evaluator version
- workflow/subagent orchestration shape

Run the same eval slice before and after the change, then compare quality, safety, task adherence, latency, and cost. A cheaper model is not an improvement if it silently regresses tool choice or groundedness; a better final answer is not enough if safety or cost breaks the operating envelope.

Recommended metadata:

- `model_version`
- `prompt_version`
- `tool_version`
- `workflow_version`
- `policy_version`
- `evaluator_version`
- `rubric_version`
- `baseline_run_id`
- `candidate_run_id`
- `rollback_target_version`

This keeps optimize loops reproducible and lets CK explain why a candidate was promoted, rejected, or rolled back.

## Red-team evidence in benchmark workflows

Adversarial tests are benchmark evidence, but they are also security artifacts. Treat attack prompts as hostile test inputs, never as instructions for the agent or operator.

Useful red-team scenario metadata includes:

- `eval_source: "red_team"`
- `attack_strategy: "leetspeak"`, `"crescendo"`, `"indirect_prompt_injection"`, or another reviewed label
- `risk_category: "sensitive_data_leakage"`, `"prohibited_action"`, `"violence"`, `"tool_misuse"`, or another policy category
- `allowed_actions` and `prohibited_actions` when an agent can call tools
- `safety_gate_version`

Red-team findings should become reviewable findings, regression scenarios, or security proof records. They should not directly tune prompts, weaken guardrails, or promote policy changes without review.

## Trace-derived eval design

When converting traces into benchmark scenarios, classify the failure before choosing the scorer. A correctness eval is useless for a faithfulness failure, and a broad semantic judge can hide the exact behavior CK needs to prevent.

Recommended scenario design:

- Start with a real trace, span, finding, review comment, or debrief that shows the behavior.
- Name the failure dimension before writing the test.
- Prefer deterministic checks for policy, schema, exact-match, capability, and regression assertions.
- Use judge-based scoring only for narrow semantic dimensions with rubrics, anchors, constrained labels, and meta-evaluation against human/golden labels.
- Keep capability evals separate from regression evals: a capability eval is a hill to climb; once CK or a host reliably passes it, promote it into a regression suite.
- Compare experiments with one changed variable at a time: prompt, model, policy artifact, router rule, retrieval strategy, or harness setting.

Useful metadata for trace-derived evals includes:

- `eval_source: "production_trace"`, `"synthetic"`, `"review_feedback"`, or `"operator_debrief"`
- `eval_mode: "deterministic"`, `"llm_judge"`, or `"human_golden"`
- `failure_dimension: "correctness"`, `"faithfulness"`, `"safety"`, `"schema"`, `"groundedness"`, or `"task_completion"`
- `judge_rubric_version` when an LLM judge is involved
- `golden_dataset_id` when human labels are used
- `experiment_variable` for one-variable-at-a-time comparisons

Cost discipline matters: keep regression suites compact and high-signal, and spend larger eval budgets on unresolved capability hills or release-confidence runs.

## External signal: GEPA holdout transfer (single external study)

An external write-up by Tim Waldin (Apr 2026) reported that GEPA-driven prompt evolution improved a Claude Haiku bug-fix benchmark from **0.6496 to 0.8462 on an unseen holdout** (**+0.1966**, 9 unseen bugs, 3 samples per prompt), with no train/holdout overlap in that setup. Source: Tim Waldin, "Using GEPA to hone Claude Haiku on GitHub bug fixes (+20% solve on untrained bugs)" (tim.waldin.net, 2026-04-19).

Treat this as one external data point, not a universal performance claim. The transferable lesson for CK is benchmark hygiene and promotion discipline:

- preserve strict optimization vs held-out split boundaries
- require explicit overlap checks between training/optimization and holdout scenarios
- use multi-sample evaluation before promotion (for example, multiple seeds/samples per candidate)
- prefer diverse training coverage; tiny narrow sets can overfit and regress on unseen cases
- promote only when held-out evidence improves without safety/regression backslide

## External optimizer interoperability (hone-style pattern)

The `twaldin/hone` project adds a useful interoperability pattern for CK benchmark operators: keep optimization outside the governed scorer, but preserve enough run context for reproducibility and promotion decisions.

Recommended practice when importing external optimizer runs:

- keep one stable scalar score channel (for ranking) and one structured trace channel (for diagnosis)
- capture scorer contract details in metadata (such as: `score_source`, `trace_format`, `trace_count`)
- record optimizer context in metadata (such as: `optimizer_framework`, `mutator`, `target_scope`, `scheduler_strategy`, `observer_mode`)
- if observer/context-updating loops are used, require a rollback guard in promotion notes (such as reverting observer updates when rolling quality drops)
- promote only when held-out evidence improves across multiple runs and safety/regression expectations still pass

This is aligned with CK’s evidence-first posture: external optimizers can search freely, but CK remains the promotion gate and audit trail.

## Blessed external comparison

The recommended first external comparison path is:

- `ControlKeel Validate` vs `OpenCode Manual Import`

This keeps the benchmark reproducible without requiring a deep native integration first.

## Subject types

- `controlkeel_validate` — direct ControlKeel validation path
- `controlkeel_proxy` — ControlKeel governed proxy path
- `manual_import` — awaiting-import run first, then import captured external output
- `shell` — scriptable subject that writes stdout or files for rescoring

## Multimodal and large artifacts

Agent traces and eval evidence can include large or non-text artifacts (screenshots, audio, video, or other binary payloads). Treat these as **referenced artifacts**:

- store the bytes in object storage or a file-backed proof bundle
- keep pointers, metadata, and integrity digests in the trace/proof record
- render or inspect them in a review surface when needed

Trace UI snapshots, PR preview screenshots, and UI diffs are evidence artifacts; store them by reference with integrity hashes and reviewer metadata.

Do not try to stuff large binaries into single database rows or tool transcripts. The durable record should stay portable and reviewable, with binaries attached by reference.

## Optional Workshop trace inputs

Raindrop Workshop snapshots can seed CK benchmark work when they are kept at the evidence boundary. Prefer importing redacted summaries or referenced artifacts rather than copying raw span payloads into benchmark metadata. Useful Workshop-derived metadata includes:

- `external_trace_source: "raindrop_workshop"`
- `trace_viewer: "local_workshop"`
- `workshop_run_count`, `workshop_span_count`, and `workshop_error_span_count`

Promotion discipline stays unchanged: Workshop traces can suggest eval candidates, but CK benchmarks and held-out evidence decide whether a policy, router, prompt, or skill change is safe to promote.

## Split and tag discipline

Benchmark scenarios already carry split-aware metadata:

- `public` for normal reusable suites
- `held_out` for reserved evaluation sets such as `policy_holdout_v1`

Each scenario also carries structured metadata that acts like behavior tags, including fields such as:

- `domain_pack`
- `task_type`
- `artifact_type`
- `security_workflow_phase`
- `memory_sharing_strategy`
- `compaction_strategy`
- any explicit `behavior_tags`

For search-sensitive agent workflows, add retrieval-specific metadata instead of relying only on aggregate wall-clock or tool-call counts:

- `search_task_type`: such as `workspace_orientation`, `symbol_lookup`, `call_site_discovery`, or `implementation_entrypoint`
- `retrieval_strategy`: such as `filesystem_find`, `filesystem_grep`, `hybrid_memory`, `ranked_code_search`, or `late_interaction_rerank`
- `orientation_metric`: such as `target_file_rank`, `hit_at_1`, `hit_at_3`, `files_read_before_target`, or `searches_before_first_read`
- `result_presentation`: such as `raw_matches`, `ranked_paths`, `grouped_files`, or `trimmed_context`

The goal is to measure whether a retrieval surface helps the agent choose the right file sooner. Faster search calls are useful, but promotion should depend on retrieval quality and held-out end-to-end outcomes, not latency alone.

**Context pruning warning**: Aggressive context pruning can "lobotomize" models. Mario found that some harnesses prune tool output after a minimum token amount, removing crucial context that models need to reason effectively. CK's compaction strategies (llm_summary, attention_guided_kv_compaction) are designed to preserve decision traceability while managing context growth, not to silently lobotomize the model.

ControlKeel now exposes split summaries and behavior-tag summaries in benchmark run metadata and exports so teams can see whether a result came from optimization-friendly coverage, held-out evidence, or both.

Benchmark run exports also include a `promotion_integrity` profile and `diagnostic_findings` payloads. These are CK-style finding maps, but they are not auto-persisted by the benchmark runner. Operators or background jobs can choose to persist them when a promotion workflow wants durable findings for missing held-out evidence, low behavior diversity, or missing classification evidence.

The intended operating model is:

1. turn recurring production failures into trace packets and failure clusters
2. promote the best candidates into curated benchmark scenarios
3. keep optimization and held-out cases separate
4. compare harness changes against both outcome quality and regression protection

This is the benchmark-side equivalent of treating evals like training data for harness engineering without letting the harness overfit the visible cases.

## Premise-refusal and dissatisfaction evals

Not every useful benchmark case is about producing the right positive answer. Some of the highest-signal CK scenarios should check whether the model refuses to over-solve a bad premise in the first place.

Two especially useful patterns are:

- **Premise-refusal or pushback cases**: prompts where the right behavior is to challenge the framing, reject the invalid premise, or ask for clarification instead of confidently producing an unsupported analysis.
- **Dissatisfaction or both-bad cases**: expert prompts where two candidate outputs can both be unsatisfactory even if neither contains a classic policy violation.

This matters because many benchmark curves overstate progress on narrow, well-specified tasks while missing failures such as:

- confidently analyzing nonsense inputs
- reasoning harder in the wrong direction instead of stopping
- producing long plausible output that still fails expert taste or task reality

For CK, the transferable lesson is not "use LLM-as-judge everywhere." It is to expand scenario design so benchmark suites include:

- invalid-premise prompts where successful behavior is explicit pushback
- expert-review prompts where "both bad" is a valid outcome class
- harder real-work prompts whose quality depends on judgment, not just factual correctness

When you need to represent those cases in run metadata, useful tags include:

- `behavior_tags: ["premise_refusal"]`
- `behavior_tags: ["clarification_required"]`
- `behavior_tags: ["over_accommodation_risk"]`
- `behavior_tags: ["expert_judgment"]`
- `behavior_tags: ["both_bad_possible"]`

If a run uses a softer scorer for these scenarios, keep that explicit in metadata and export notes rather than pretending it is as deterministic as CK's normal scanner-based path.

## Terminal Bench and minimal harnesses

Terminal Bench is a coding agent benchmark that provides only two tools: send keystrokes to a tmux session, and read the output of that tmux session. No file tools, no sub-agents, none of the complexity found in modern harnesses. Despite this minimalism, Terminal Bench consistently scores higher than native harnesses across model families.

This suggests we are still in the "yolo around and find out" phase of coding agents—their current form is not their final form. Simplicity can outperform complexity when the complexity is unnecessary or poorly designed. For CK, this reinforces the importance of:

- Minimal, stable tool contracts over feature bloat
- Progressive discovery over always-loaded context
- Measuring what actually matters (task completion) over proxy metrics

The lesson is not "remove all tools" but "add tools deliberately and measure their impact."

For multi-agent memory experiments, use metadata to describe the strategy honestly rather than claiming native support CK does not implement itself. Examples:

- `memory_sharing_strategy: "summary"`
- `memory_sharing_strategy: "rag_retrieval"`
- `memory_sharing_strategy: "full_pass_through"`
- `memory_sharing_strategy: "latent_briefing"`
- `memory_sharing_strategy: "late_interaction"`
- `memory_sharing_strategy: "multi_vector_maxsim"`
- `memory_sharing_strategy: "hybrid_late_interaction"`
- `compaction_strategy: "llm_summary"`
- `compaction_strategy: "attention_guided_kv_compaction"`

That lets CK compare governed runs across the same suite while keeping the benchmark evidence clear about what was actually used.

When the run also depends on host-managed file memory, record that separately instead of smuggling it into a generic "memory" label. Useful values include:

- `memory_surface: "typed_memory_only"` — CK memory/proofs/resume state only
- `memory_surface: "filesystem_only"` — repo files, notes, or mounted directories only
- `memory_surface: "hybrid_typed_plus_filesystem"` — CK typed memory plus host file memory
- `memory_surface: "host_project_memory"` — host-native project memory files such as repo-scoped instruction/memory documents

This makes it easier to compare "agent plus terminal" memory setups against governed typed-memory setups without pretending they are the same surface.

### Retrieval strategy metadata

When benchmarking retrieval quality over CK memory, tag the retrieval backend:

- `retrieval_strategy: "single_vector"` — current pgvector cosine similarity (default)
- `retrieval_strategy: "bm25"` — keyword/lexical baseline
- `retrieval_strategy: "hybrid_bm25_vector"` — combined lexical + dense
- `retrieval_strategy: "late_interaction"` — multi-vector late interaction (ColBERT-style MaxSim or similar)
- `retrieval_strategy: "cross_encoder_rerank"` — retrieve then rerank with a cross-encoder
- `retrieval_strategy: "late_interaction_rerank"` — retrieve then rerank with late interaction scoring

This vocabulary exists so future retrieval experiments can be compared fairly. See `docs/idea/2026-late-interaction-retrieval-research.md` for the research motivating multi-vector and late-interaction approaches.

### Runtime experiment metadata

When comparing experimental agent runtimes, keep the runtime shape explicit in metadata instead of hiding it behind a single score.

Useful fields include:

- `tool_call_surface: "json_schema"` — structured JSON or schema-bound tool calls
- `tool_call_surface: "terminal_native"` — terminal-style command blocks or delimiter formats that lean on pretraining-familiar syntax
- `tool_call_surface: "mcp_native"` — direct MCP tool/resource surface
- `tool_call_surface: "plain_text_delimited"` — ad hoc text protocol with stop tokens or sentinels
- `tool_call_surface: "text_act_format"` — explicit text-native act protocol that an adapter lowers into normal tool events
- `control_flow_surface: "single_pass"` — one forward reasoning pass with no recursive decomposition
- `control_flow_surface: "search_loop"` — iterative planner/executor loop over a shared context
- `control_flow_surface: "recursive_repl"` — recursive environment exploration or sub-call pattern
- `loop_shape: "closed"` — bounded delivery loop with an intended finish condition
- `loop_shape: "open"` — exploratory or optimization loop with no guaranteed finish by the run boundary
- `progress_contract: "finish_slice"` — expected outcome is a completed reviewable slice
- `progress_contract: "shrink_search_space"` — expected outcome is narrower uncertainty or fewer remaining candidates
- `progress_contract: "improve_metric"` — expected outcome is measurable benchmark or quality improvement
- `handoff_contract: "relay_structured"` — baton passing via explicit plan, blockers, evidence, and next-step state
- `validator_feedback: "per_iteration"` — validators or review checks fire between worker iterations
- `protocol_adapter: "model_facing_adapter"` — a layer rewrites the model-facing protocol without replacing the underlying runtime loop
- `parser_recovery_mode: "explicit_intent_only"` — malformed explicit tool attempts may be recovered, but missing intent is not guessed
- `prompt_optimization_method: "gepa"` — adapter instructions tuned through GEPA or similar prompt optimization
- `artifact_scope: "model_scoped"` — prompt/runtime artifacts are keyed to a specific model rather than treated as universal behavior

These fields help distinguish "done by morning" runs from "better by morning" runs without pretending they should be judged the same way.

- `control_flow_surface: "typed_runtime"` — recursion or decomposition handled by a constrained typed runtime rather than improvised free-form control flow

This gives CK a way to compare experiments such as terminal-native tool syntax, recursive language-model loops, or typed functional runtimes without pretending those are all first-class shipped CK targets. The rule is simple: benchmark the concrete runtime contract that actually ran, record it honestly, and compare it on the same held-out suite.

Protocol-adapter experiments are a clear case of why this metadata matters. Sometimes the runtime loop is fine and the weak point is the model-facing interface: provider-native JSON tools are brittle, stop reasons are misleading, or smaller models fail to emit valid syntax. In those cases, the experiment is not "new runtime versus old runtime." It is "same runtime, different adapter contract." CK should record that distinction explicitly.

### Skill activation and detection metadata

When benchmarking skill routing, selection, and activation behavior, tag scenarios with the expected detection properties so results are comparable across runs and agent surfaces.

**Detection confidence levels** (mirrors SkillGym's normalized session report model):

- `skill_detection: "explicit"` — agent invoked the Skill tool directly by name; highest-confidence evidence
- `skill_detection: "strong"` — agent read the skill's `SKILL.md` file as observed in file-read events
- `skill_detection: "medium"` — indirect evidence such as a matching command or tool call consistent with the skill
- `skill_detection: "weak"` — heuristic or inferred; pattern-matched from output text only

**Skill read tracking:**

- `observed_skill_reads: "required"` — scenario asserts that specific `SKILL.md` files were read, not just that the skill was invoked
- `observed_skill_reads: "ordered"` — scenario requires skill files to be read in a specific sequence (e.g., routing skill before the target skill)
- `observed_skill_reads: "exclusive"` — scenario asserts that no unexpected skills were activated (single-skill gate)

**Token snapshot baseline:**

- `token_snapshot: "enabled"` — this scenario has a captured token-usage baseline and should be flagged if usage regresses beyond the configured tolerance
- `token_snapshot: "tolerance_10pct"` — allow up to 10% token growth before flagging as a regression
- `token_snapshot: "tolerance_25pct"` — allow up to 25% token growth (useful for non-deterministic or multi-tool scenarios)

Token snapshots catch context-bloat regressions: a skill that previously loaded in 400 tokens should not silently balloon to 4000 tokens after a body edit. Update snapshots explicitly (`--update-snapshots` equivalent in the benchmark runner) and treat unexplained growth as a finding, not a no-op.

The same idea applies to harness constraints enforced through tests and lints about source shape (file size, layering boundaries, dependency edges). If those constraints exist to protect context windows and keep work local, treat unexplained growth and repeated violations as benchmarkable regressions, not as one-off review comments.

**Ordering and sequence assertions:**

For scenarios where tool invocation order matters (e.g., `ck_validate` must precede `ck_review_submit`, or a routing skill must activate before the domain skill), record the expected sequence in metadata:

- `tool_call_sequence: "required"` — scenario verifies that tool calls occurred in a specific order
- `file_read_sequence: "required"` — scenario verifies that file reads occurred in a specific order
- `skill_activation_sequence: "required"` — scenario verifies that skill A activated before skill B

These tags make it clear in benchmark exports that a passing result depended on ordering, not just presence, so regressions that reorder but still complete are caught rather than silently passing.

## Rollout abort threshold

When using benchmark scores as a release gate for agent harness changes (model swaps, system prompt rewrites, tool access changes), use these thresholds as the abort signal:

- **Score drop**: abort rollout if the judge-averaged quality score drops **≥ 0.15** against the current production baseline
- **Statistical window**: require a minimum of **200 interactions** before computing the gate decision
- **Significance**: require **p < 0.05** on the quality delta before promoting or aborting
- **Cohort ladder**: gate each promotion step (10% → 20% → 50% → 100%) against a fresh window, not the cumulative pool

If the abort threshold triggers: flip traffic back to stable, open a finding with the regression cohort attached, and treat it as a new failure cluster entering the improvement loop. Do not re-promote until the root cause is identified and the held-out suite passes.

For minority or experimental model integrations (non-dominant provider), route at 100% rather than applying the standard traffic-proportional rate — minority models never reach statistical significance fast enough to gate a rollout decision at low routing rates.

Record rollout gate decisions in benchmark run metadata using:

- `rollout_gate: "score_drop_abort"` — rollout aborted by quality regression
- `rollout_gate: "score_drop_threshold"` — threshold value used (e.g. 0.15)
- `rollout_gate: "significance_window"` — interaction count at gate decision
- `rollout_gate: "cohort_pct"` — traffic percentage at abort time

## Pre-flight destructive capability checklist

Before granting an agent production access or expanding its capability surface, answer these five questions. A single "yes without approval" is a blocker:

1. **Can it delete data?** — write access to production databases, object storage, or durable state without a checkpoint or dry-run gate.
2. **Can it touch backups?** — read or write access to backup targets, snapshot buckets, or recovery state.
3. **Can it rotate secrets?** — ability to invalidate, regenerate, or reassign credentials, API keys, or IAM roles.
4. **Can it change infrastructure?** — Terraform, CDK, cloud console, or equivalent that mutates running infrastructure.
5. **Can it do any of the above without human approval?** — no review gate, no `ck_review_submit`, no `requires_human_review` finding raised.

If the answer to question 5 is yes for any of 1–4, the task is a capability egress violation under CK policy (`network_default: deny`, `approval_path: ck_review_or_trusted_human`). Resolve with an explicit scoped allowlist and a `ck_review_submit` approval before granting access.

CK's `fast_path` scanner catches the most common destructive shell patterns reactively (repo-wide `git checkout`, `git reset --hard`, broad `rm -rf`, etc.) — this checklist is the proactive gate that runs before those patterns can even reach execution.

## Web UI quick presets

On `/benchmarks`, use **Quick presets** (OpenCode comparison, ControlKeel validate only, Validate + governed proxy) to fill the subject and baseline fields, then adjust if needed. The subjects field still accepts a comma-separated list and supports browser autocomplete from **Available subjects**.

## OpenCode and host-governance procedures

Procedural setup, import payload references, host-mode commands, and the surface evaluator live in [benchmark-guide.md](benchmark-guide.md). Current published results and interpretation live in [benchmark-evidence.md](benchmark-evidence.md). Keep this document focused on benchmark concepts, metadata discipline, and operator guidance.

A full evaluation pass should include both layers:

1. deterministic benchmark suites with `controlkeel_validate` for scanner/domain/security coverage;
2. host-agent surface evaluation for CLI, MCP, skills, hooks/plugins/extensions, attach assets, and event evidence.

## Interpretation

Use benchmark results as product evidence, but keep the claim precise:

- ControlKeel ships a blessed OpenCode comparison path
- external subjects can be imported or scripted
- not every external agent is zero-config or bridge-native yet

When using benchmarks to improve a harness, prefer:

- small hand-curated suites with strong tags over large noisy dumps
- explicit holdout suites for promotion decisions
- trace-derived eval candidates when failures recur across real sessions
- regression-safe promotion, not score chasing on one visible split

For GEPA-style text optimization specifically:

- treat prompts, system instructions, and lightweight text configs as candidate artifacts
- keep the optimizer outside the governed scoring surface
- enforce zero overlap between optimization/training cases and held-out promotion cases
- run multi-sample candidate evaluations (not single-run score snapshots) before promotion
- use CK exports and run metadata as the audit trail for what changed and why it was promoted
- include optimizer-run metadata (such as scheduler/observer/target-scope settings) so later comparisons stay apples-to-apples

For experimental recursive or typed-runtime systems, the same rule applies: benchmark the concrete runtime behavior that actually ran. Do not promote based on architectural taste alone. If the experiment matters, record it honestly in run metadata and compare it on the same held-out suite.

### Delegation and subagent surface checks

When evaluating hosts or extensions that delegate to child agents, score the delegation surface explicitly instead of treating it as a generic model call. A useful benchmark or surface-evaluation packet should record:

- **Depth and recursion guards**: maximum delegation depth, whether nested delegation is blocked or bounded, and what happens when the limit is reached.
- **Isolation model**: fresh context, forked session, isolated worktree, or shared workspace; include whether parallel children can clobber each other.
- **Fork semantics and reproducibility**: whether fork/fresh-context behavior is declared in repo-visible config or only through ambient env/runtime switches; hidden toggles should be documented explicitly because they weaken replayability and file-based review.
- **Tool/MCP/skill/extension allowlists**: which tools are inherited, overridden, or disabled for each child agent.
- **Async/background observability**: status files, event logs, progress state, interrupt behavior, and completion receipts.
- **Decision channels**: how a child asks for clarification or escalates a blocker instead of guessing.
- **Handoff contracts**: what chain/parallel steps pass forward, how outputs are summarized, and whether artifacts such as context, plan, diff, or review files are durable.
- **Budget and timeout controls**: per-child token/time limits, concurrency limits, fallback behavior, and failure reporting.

For CK, these checks should be evidence fields in benchmark exports or surface-evaluation summaries. They should not be hidden inside a vague “multi-agent” label.

Policy-training promotion gates now carry the same integrity stance. A candidate policy artifact must have validation, held-out, and baseline evidence before promotion can succeed, and the gates include diagnostic finding payloads for review surfaces that want to persist the warning.
