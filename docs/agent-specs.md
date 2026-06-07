# Agent and Task Specs

ControlKeel treats an agent or task spec as the portable behavior contract for an AI system: what the agent is supposed to do, what it must not do, what domain vocabulary matters, which actions it may take, and which evidence proves it stayed inside the envelope.

Specs are intentionally independent of implementation. The same spec should be able to evaluate a raw host, a CK-attached host, a typed runtime, a new prompt, or a future model without rewriting the contract.

## Why specs belong in CK

Traditional evals often start as input/output examples. That is useful, but production agents need more context:

- domain and business rules that should never be violated
- ontology or dictionary terms that constrain valid substitutions
- user roles, rights, and permission state
- allowed and prohibited tool or infrastructure actions
- robustness requirements such as typos, paraphrases, frustrated users, ambiguity, and adversarial wrapping
- linked policy packs, review gates, and benchmark suites

CK already records reviews, findings, proofs, trace-derived eval candidates, and benchmark scenarios. Agent and task specs make the intended behavior explicit so CK can compare that intent against observed behavior.

## Recommended metadata shape

Use these fields in benchmark scenario metadata, review plan refinement packets, and imported trace/eval envelopes when the scenario depends on a reusable behavior contract:

- `agent_spec_id`: stable identifier for the role or behavior contract
- `agent_spec_version`: version of the contract under evaluation
- `task_spec_id`: stable identifier for a task-level contract
- `agent_role`: support agent, code reviewer, deployment agent, sales assistant, or another reviewed role label
- `task_scope`: what the agent is expected to accomplish
- `out_of_scope`: topics, actions, or requests the agent should refuse, redirect, or escalate
- `business_rules`: domain/product rules that must hold
- `domain_terms`: ontology, dictionary, or internal terminology that constrains valid substitutions
- `persona_or_actor_context`: user role, customer tier, permission state, or operating context relevant to behavior
- `allowed_actions`: tool or infrastructure actions inside the operating envelope
- `prohibited_actions`: actions that require refusal, escalation, or a new approval gate
- `robustness_requirements`: perturbations behavior should survive, such as typos, paraphrases, ambiguity, or adversarial wrapping
- `linked_policy_packs`: CK policy packs that govern the scenario
- `linked_benchmark_suites`: suites that should be checked before promotion
- `promotion_gates`: evidence required before the agent/prompt/tool change can ship

## Operating loop

Keep the loop evidence-first and human-gated:

1. Write or reference the agent/task spec.
2. Submit plans with `ck_review_submit`, including spec identifiers and relevant boundaries.
3. Validate generated code, config, shell, or text with `ck_validate`.
4. Record violations or gaps as findings.
5. Convert recurring trace failures into benchmark drafts and materialized scenarios.
6. Promote changes only when held-out benchmark evidence, safety checks, and review gates pass.

The contract is:

```text
agent/task spec -> review boundaries -> validation findings -> trace failures -> benchmark scenarios -> held-out promotion evidence
```

## Boundaries

Do not let a spec silently mutate runtime behavior:

- no automatic prompt, router, policy, or skill rewrites from spec text
- no formal-verification claims for black-box LLM behavior
- no broad evaluator abstraction before concrete benchmark evidence exists
- no permission expansion without `ck_review_submit` approval and explicit capability boundaries

Specs should feed findings, reviews, benchmarks, and proof records. They should not become hidden authority.
