# Autonomy and findings

ControlKeel records findings and can suggest fixes, but it does **not** promise fully unsupervised autonomy for every risk level. Use this page as the single reference for how severity maps to expected human involvement.

CK now also exposes a **session autonomy profile** and an **outcome profile**. That is how ControlKeel makes the operator model explicit instead of implying that every governed session is the same.

## Session autonomy profiles

These are session-level operating modes, distinct from host integration autonomy labels such as `policy_gated` in the support matrix.

| Session mode | Meaning |
|----------|----------------|
| **advise** | CK is helping plan, review, and package context, but the human is still steering each step. |
| **supervised_execute** | The agent can execute, but high-risk or approval-heavy work keeps human gates close to the loop. |
| **guarded_autonomy** | The default CK operating mode: agents can work, while findings, proofs, budgets, and routing controls remain active. |
| **long_running_autonomy** | The session is keyed to an explicit outcome/KPI or sustained multi-task objective, so CK treats it as an ongoing improvement loop. |

These profiles are derived from explicit metadata when present, and otherwise inferred from risk, constraints, cyber access mode, and session shape.

## Outcome profiles

CK distinguishes between:

- **delivery** sessions: complete the current task or release milestone safely
- **kpi** sessions: move an explicit outcome target such as reducing a vulnerability backlog or reaching deploy-ready with no critical findings

That profile is now surfaced in:

- MCP `ck_context`
- `GET /api/v1/sessions`
- `GET /api/v1/sessions/:id`
- `GET /api/v1/improvement`
- `/ship`

So operators can tell whether a session is just trying to finish work, or whether it is meant to run as a longer-horizon control loop.

The session improvement loop also exposes two software-law diagnostics:

- `bottleneck_summary` identifies the likely serial constraint before CK recommends more parallel work. It distinguishes unresolved findings, pending review readiness, missing deploy-ready proof, budget pressure, and thin trace evidence.
- `ownership_summary` reports concentration across available task owners, review submitters, and finding categories. It is intentionally evidence-backed and only warns when the current data shows enough concentration to be useful.

Both diagnostics also provide CK-style `diagnostic_findings` payloads. CK does not auto-persist them by default, which avoids duplicate findings during normal dashboard refreshes; callers can persist them when they want a durable review item.

## Provider-backed vs heuristic mode

- **LLM advisory** (extra pattern review on top of FastPath and Semgrep) runs only when a provider is configured. Validate and MCP `ck_validate` responses include an **`advisory`** object describing whether the advisory layer ran or was skipped (for example no API key).
- **Heuristic mode** still supports governance, MCP tools, proofs, skills, and benchmarks; model-backed advisory and some compilation paths are limited.
- **Destructive shell tripwires** run even in heuristic mode. Repo-wide cleanup commands such as `git checkout -- .`, `git reset --hard`, `git clean -fd`, and broad `rm -rf` scopes are blocked with checkpoint and rollback guidance so agents cannot treat them as ordinary shell mutations.

## Severity and default gates

These are **product expectations** for reviewers, not automatic enforcement rules in every deployment:

| Severity | Typical gate |
|----------|----------------|
| **critical** | Human review required before production or high-impact action. |
| **high** (especially security) | Review and approve before merge or release. |
| **high** (non-security) | Review recommended before marking work complete. |
| **medium** | Review when convenient; guided fixes and warnings are common. |
| **low** | Governance still records outcomes; lower friction. |

Destructive or irreversible actions should stay behind explicit approval, proofs, and policy—regardless of severity.

## Human wake-up surfaces

CK is designed to preserve a few places where the human should wake back up instead of letting the agent loop stay frictionless.

A useful distinction is between:

- **mechanical feedback**: issues the agent can fix by following established rules (formatting, missing tests, small refactors)
- **judgment calls**: changes that require a human to re-activate domain and production context (permissions, migrations, auth boundaries, irreversible operations)

CK is designed to push as much mechanical feedback as possible into automated findings and review guidance, while still surfacing explicit human-gate hints for judgment calls.

Specific judgment call examples from practice:
- **Database migrations**: Require human review because they depend on locks, data size in production, and rollback safety
- **Permissioning changes**: Often underdocumented and can have security implications that agents miss
- **Dependency additions**: Require human judgment about maintainer trust, license compatibility, and long-term maintenance
- **Architecture decisions**: Changes to system boundaries, data flow, or service contracts

That expectation already shows up in the product through:

- `human_gate` execution modes for review/release-oriented task nodes
- architecture-first planning for higher-risk work
- rollback boundaries on task plans
- human gate hints attached to findings in Mission Control

In practice, CK is telling the operator not to treat every generated diff the same. Narrow, reversible fixes can stay low-friction. Architecture decisions, release-boundary changes, destructive actions, and similarly high-consequence changes should pull the human back into the loop.

## Agent slop and error compounding

Mario's term "boooos" (errors) captures a real problem: agents compound errors with serial learning, no bottlenecks, and delayed pain. When you replace one human with ten agents, the amount of code you can review drops dramatically while the error rate ("boooos per day") increases.

Key patterns of agent slop:

- **Review capacity mismatch**: Humans cannot review all agent-generated code. Review agents help but don't solve the problem—they learn complexity from internet garbage code (90% of code on the internet is "our old garbage").
- **Agent-optimized progress**: Agents are optimized to write code that runs, makes progress, and unblocks themselves. This leads to patterns humans would avoid—silent defaults, brittle recovery paths, and many more failure conditions. Humans feel bad writing this kind of code; agents don't feel anything, so they keep generating it.
- **Local decisions, global mess**: Agents make local decisions without full context, especially when the codebase doesn't fit in context. This leads to tangled abstractions, duplication, and "enterprise-grade complexity within two weeks."
- **Specs as programs**: A sufficiently detailed spec is a program. When you leave blanks in a spec, the model fills them with garbage learned from internet training data.
- **Delayed pain**: Agents happily keep adding errors to the codebase. Humans feel pain, which is a useful property—it drives refactoring, quitting, or blaming others into fixing it. Agents don't feel pain, so they don't stop.

CK's guardrails against agent slop:

- **Scoped tasks**: Require that agents can find all context needed to do the job (modularize the codebase)
- **Evaluation functions**: Give agents a function to evaluate how well they did (hill climbing, auto-research)
- **Critical vs non-critical distinction**: Non-critical code can use agents; critical code requires human line-by-line review
- **Human bottlenecks as feature**: Humans limit error accumulation simply by being slow. CK doesn't try to remove this bottleneck—it tries to make the bottleneck effective.

The goal is not to eliminate all agent-generated code. The goal is to:
- Use agents for non-mission-critical, boring, or well-scoped tasks
- Polish critical features with agents, but write the core by hand
- Keep the amount of generated code you need to review manageable
- Accept that "slow the fuck down" is valid advice when everything breaks

CK does not claim to perfectly classify every risky change type today. The current product stance is narrower and more honest: keep the review boundary explicit, keep rollback and proof state visible, and increase human attention as impact and irreversibility go up.

Plan reviews now also include decision hygiene prompts in review-gate metadata. These prompts are tied to concrete signals such as high scope, missing validation evidence, repeated plan depth, or missing rejected options. They are designed to trigger inversion, evidence, sunk-cost, and alternative checks without turning the UI into generic advice.

## Relation to Mission Control

Mission Control surfaces **human gate hints** next to each finding so operators see the same stance the docs describe. Approve, reject, and proof flows remain the source of truth for recorded decisions.

## Appendix: autonomy ladder mapping

People often describe autonomy as a ladder that starts with autocomplete and ends with a "dark factory" where you only provide intent and review outcomes. CK does not treat that ladder as a permission grant; it treats it as an **operating posture** that must be backed by guardrails, proofs, and explicit human gates.

One practical mapping:

- **Level 0–1 (autocomplete / edits)** → **advise**
  - CK is mostly used for quick reference, fast validation (`ck_validate`), and to keep a light record of risks.

- **Level 2 (pair programmer chat)** → **advise** / **supervised_execute**
  - Humans stay closely in the loop. CK can help translate intent into smaller verifiable steps and surface findings early.

- **Level 3 (AI generates most code; human reviews)** → **supervised_execute**
  - CK expects stronger verification artifacts (tests, repro steps, proof captures) before calling work complete.

- **Level 4 (delegating to agents; async execution)** → **guarded_autonomy**
  - CK focuses on keeping the loop observable: findings, proof artifacts, budgets, and review gates.

- **Level 5 ("factory" / black box automation)** → **long_running_autonomy** (only when outcomes and gates are explicit)
  - CK's stance: autonomy is acceptable only when the system is verifiable (tests + proof + monitoring), risky boundaries are scoped, and irreversible actions remain human-gated.

If you are trying to move "up the ladder", the highest-leverage work is usually not more prompts; it is building verification and governance surfaces so outcomes stay reviewable even when code is not.
