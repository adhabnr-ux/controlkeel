# Explaining ControlKeel

This document is the plain-English answer to:

- what is ControlKeel?
- why does it exist?
- what problem does it solve?
- how do you use it?
- how does it work?
- what makes it different from hosts, agents, IDEs, plugins, or post-hoc code review tools?

## The shortest explanation

**ControlKeel is the control plane for agent-generated software delivery.**

It does not try to be the coding model, IDE, or chat interface. It sits around the agent loop and adds the parts that usually break first in real work:

- reviewability
- scoped execution
- validation before risky actions
- findings and approval gates
- proofs and audit history
- budget and provider control
- task continuity and resume context
- release readiness

In one line:

**Agents generate output. ControlKeel turns that output into governed, reviewable, production-minded delivery.**

## The problem ControlKeel solves

Modern coding agents are very good at producing code, shell commands, plans, and edits.

They are much less reliable at:

- staying inside a real trust boundary
- knowing when a command is too destructive
- preserving enough context to be reviewable later
- proving what happened
- adapting their behavior to compliance, approval, or release risk
- keeping cost and provider behavior under control
- working consistently across many hosts and agent products

Without a layer like ControlKeel, the usual pattern is:

1. the host gives the model tools
2. the agent edits files and runs commands
3. humans hope the behavior was safe and correct
4. only after the fact do people try to reconstruct what happened

That is fine for throwaway work. It gets shaky fast for real repos, regulated work, shared teams, and expensive or high-risk changes.

ControlKeel exists because **agent capability is not the same thing as delivery safety**.

### The "unknown unknowns" problem in domain knowledge persistence

Industry practitioners have identified a specific pain point that makes working with AI agents miserable: **having to re-explain domain knowledge in every new session**.

Consider a concrete case: suppose you have a rule that "using BigInt in this repo is bad for complex reasons." The explanation might be 1,000 tokens of technical detail about serialization, performance characteristics, or compatibility issues. Now multiply this by hundreds of similar domain-specific rules, and you have 500,000+ tokens of mandatory domain knowledge.

You face two options:

**Option 1: Make it directly visible (AGENTS.md)**
This works if the agent is good enough, but the problem is scale. Accumulate enough of these complex explanations and including them in context will immediately downgrade model performance (effectively to GPT-2 level) and cost a fortune in tokens.

**Option 2: Make it searchable (RAG, vector databases, etc.)**
The problem is that the AI cannot magically guess when it needs that bit of knowledge. When writing a JavaScript function, it will not stop and think: "wait, perhaps there is some part of the domain that tells me BigInts are bad and I should start looking for it?" It will just use BigInts. It does not occur to the agent that there is something to search for.

This manifests in three ways:

- **AGENTS.md becomes shelfware**: Either agents ignore it, or it becomes too large to include without degrading model performance (500k+ tokens of mandatory domain knowledge is common in complex domains)
- **RAG fails on unknown unknowns**: Agents cannot magically guess when they need to search for specific domain knowledge. They won't stop mid-task to think "perhaps there's a domain rule about BigInt being bad here" — they just use BigInt
- **Skills are impractical to maintain**: You'd need hundreds or thousands of domain-specific skills to cover all possible knowledge subsets, which is unsustainable manual work

The fundamental issue is that current approaches force a false choice:
- **Make domain knowledge visible** (include it in context): Too large to fit without causing context rot and performance degradation
- **Make domain knowledge searchable** (use RAG): Agents can't guess what they need to search for

ControlKeel solves this through a **layered knowledge system**:

- **Typed memory with citations** (`ck_memory_record`, `ck_memory_search`, `ck_memory_archive`): Structured, citable knowledge persistence. Future agents retrieve specific domain decisions without operator re-explanation
- **Proof bundles**: Durable evidence of what worked, what failed, and why — capturing empirical domain knowledge that static documentation cannot contain without becoming unmanageable
- **Resume packets**: Session handoff carries forward actual working state, not just static documentation. New sessions resume with context of what was being worked on
- **Policy packs**: Domain-specific rules (HIPAA, OWASP, etc.) are enforced automatically — agents don't need to be told "don't do X" repeatedly because the governance layer prevents it
- **Findings as living knowledge**: Every `ck_finding` becomes part of the permanent project knowledge base. When an agent discovers "BigInt is bad here for reasons Y," that finding persists and guides future sessions
- **Context compaction with protected tail**: Intelligent compaction prevents context rot while maintaining decision traceability
- **Workspace snapshots**: Actual codebase state is captured, not descriptions — eliminating "it worked on my machine" knowledge gaps

The key insight: CK doesn't try to dump all domain knowledge into context (which fails) or expect agents to magically search for what they need (which also fails). Instead, it builds a system where:
- High-frequency rules are enforced via policy packs
- Decisions and findings are recorded in typed memory with citations
- Session state is preserved via resume packets and proofs
- Retrieval is explicit and ranked, not guesswork

This transforms domain knowledge from something you must repeatedly explain into something the system remembers and enforces.

## The value proposition

ControlKeel gives you a governed agent workflow without replacing the agent you already like.

The main value is:

- **Safer execution**: CK validates risky code, config, text, and shell content before it becomes action.
- **Better context**: CK gives agents grounded repo, task, proof, and workspace context instead of relying on giant prompts or vague memory.
- **Reviewability**: CK turns work into findings, review packets, approvals, and proof bundles that humans can inspect.
- **Cross-host consistency**: CK gives a stable governance loop across hosts like Claude Code, Codex CLI, OpenCode, Copilot, Cline, Windsurf, Continue, and others.
- **Production orientation**: CK is about shipping safely, not just generating code quickly.
- **Recovery path**: even if another tool already changed the repo, CK can bootstrap into the project and bring the work back into a governed loop.
- **Managed decomposition**: CK keeps the manager layer explicit by recording how work is split, where review gates sit, and which steps are effectively delegated, recursive, or evidence-gated.
- **Explicit harness policy**: CK derives the operational policy around the work too: which tool classes can run concurrently, how compaction should step down, which failures need in-loop recovery paths, and what isolation delegated mutation should require.
- **Stable context contract**: CK treats the working context as something operators should be able to inspect and reason about. It prefers bounded context, versioned tool contracts, and explicit retrieval over silent prompt mutation.
- **Owned memory**: CK keeps durable state in typed memory, proofs, traces, and resume packets that you can inspect and carry across hosts instead of treating provider-managed session state as the system of record.
- **Honest memory**: CK treats memory retrieval and memory integration as different jobs. It can return ranked, citable memory hits, but it does not pretend that retrieving a note is the same thing as correctly integrating it into the current reasoning.
- **Observable agent work**: CK keeps recent events, runtime context integrity, findings, review packets, and proofs visible so compaction and high-impact actions do not disappear into a black box.
- **Truthful extensibility**: CK favors real host-native surfaces such as skills, plugins, hooks, commands, and runtime bundles over shallow “universal” claims.
- **Portable provider choice**: CK keeps provider and fallback behavior explicit so teams are not trapped inside a single host-managed runtime.
- **Human judgment stays central**: CK makes agent work feel like engineering again by turning vague delegation into a bounded loop: humans set the mission, constraints, taste, budget, and stop rules; agents make scoped attempts; CK records the score through findings, proofs, approvals, and cost signals.

For defensive security teams, the same value proposition becomes:

- CK keeps vulnerability work inside an explicit detect-triage-patch-validate-disclose loop.
- CK defaults to redacted disclosure and proof-backed patch validation.
- CK distinguishes normal governed coding from higher-risk reproduction work with cyber access modes.
- CK stays defense-first; it does not present itself as a generic exploit automation product.

## What ControlKeel is not

ControlKeel is not:

- another foundation model
- another IDE
- a prompt marketplace
- a generic “AI assistant” shell wrapper
- an unsupported universal integration that claims to deeply support every host
- only a code scanner
- only a code review bot

It is specifically the **governance and delivery layer above generators**.

## How to explain it to someone in one minute

You can say:

> ControlKeel is the layer that sits between coding agents and production work. It does not replace Claude Code, Codex, OpenCode, or Copilot. It governs them. It gives agents bounded context, validates risky work, records findings, drives approvals, stores proof bundles, tracks budgets and providers, and keeps work reviewable across hosts. The point is not “more AI.” The point is making agent work safe enough, traceable enough, and structured enough to actually ship — while preserving the human judgment that makes software engineering software engineering.

That also means CK is intentionally skeptical of hype around unsupervised multi-agent product delivery. It is much better at making narrow, reviewable overnight slices credible than at pretending a pile of loosely directed agents can autonomously build robust user-facing software from scratch.

CK also makes the operating model explicit: it tells you whether a session is effectively advise-only, supervised, guarded autonomy, or long-running outcome work, and whether the current goal is task delivery or a KPI.
It also now derives a task augmentation brief so agents start from a scoped, reviewable problem frame instead of a vague ticket alone.

## How people use ControlKeel

The normal flow is:

1. install ControlKeel
2. bootstrap the repo with `controlkeel setup`
3. attach a supported host with `controlkeel attach <host>`
4. let the host use CK through local MCP, native skills, plugins, hooks, commands, or runtime bundles
5. inspect status, findings, proofs, and review state through the CLI or web app

Typical commands:

```bash
controlkeel setup
controlkeel attach opencode
controlkeel status
controlkeel findings
controlkeel proofs
controlkeel help
```

Typical web surfaces:

- `/start` for onboarding and execution brief creation
- `/missions/:id` for Mission Control and approvals
- `/findings` for governed findings
- `/proofs` for proof bundles
- `/ship` for release readiness and outcome metrics
- `/skills` for host/install/export compatibility

## How ControlKeel works

At a high level, CK runs a governed lifecycle around agent work:

1. **Intent intake**
   The user describes the work.

2. **Execution brief**
   CK compiles the practical boundary: risk tier, constraints, compliance, open questions, and delivery posture.

3. **Execution posture**
   CK decides how the work should be approached:
   - read-only virtual workspace first for discovery
   - typed memory/proofs/traces for durable state
   - typed or code-mode runtimes when large API/tool surfaces make that better
   - shell as the fallback mutation surface, with stronger approval pressure

4. **Runtime recommendation**
   CK recommends the best available attach/runtime path based on the brief and what is already attached or configured in the workspace.

5. **Task graph and routing**
   CK turns work into task state, routing hints, and reviewable progress.

   CK also derives a decomposition layer for that graph: node type, context strategy, depth, and review requirements. That gives both humans and hosts a shared view of how the work is being managed, not only what the task titles happen to be.

6. **Validation**
   CK validates code, config, shell, and text through `ck_validate`, FastPath, Semgrep, optional advisory review, trust-boundary checks, and destructive-operation tripwires.

7. **Findings and approvals**
   CK records governed findings, human gate hints, and review decisions.

8. **Proof capture**
   CK creates proof bundles so the final state is inspectable later.

9. **Ship metrics and benchmarks**
   CK tracks readiness, outcomes, and comparative evidence.

For `security` sessions, CK makes that lifecycle explicit:

- discovery
- triage
- reproduction
- patch planning
- patch validation
- disclosure and release readiness

## What the agent actually sees

When an agent uses ControlKeel, it does not just get “more prompt.”

It gets governed tools and structured context such as:

- `ck_context`
- `ck_validate`
- `ck_finding`
- `ck_budget`
- `ck_route`
- `ck_delegate`
- skill discovery and skill loading
- proof, memory, and review state

That means the agent can:

- ask CK for the current task and workspace context
- validate risky content before execution
- record findings instead of hiding them
- check budgets and routing
- use CK-native skills and hooks
- operate with resume context and proof continuity

This is very different from a host giving the agent raw shell and hoping it behaves.

## What makes ControlKeel different

### 1. It governs the delivery layer, not just the prompt

Most tools help an agent produce output.

ControlKeel helps you govern:

- whether the output should be trusted
- whether the action should run
- what proof exists
- what review state exists
- whether the work is actually ready to ship

### 2. It keeps support claims honest

Many tools blur together:

- native integration
- prompt compatibility
- “works if you manually copy this file somewhere”
- “maybe you can point it at an endpoint”

ControlKeel keeps those separate. It models hosts as typed integration rows with support classes such as:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

That matters because not every host actually supports the same things.

### 3. It supports agents and hosts in both directions

ControlKeel is not only “host uses CK.”

It also supports “CK runs or routes agent work” through:

- attach flows
- runtime exports
- provider brokerage
- hosted MCP
- A2A
- delegated execution

So the relationship is two-way:

- **agents use CK** for context, validation, findings, budgets, review, and skills
- **CK uses agents** for execution, routing, and host-specific runtime paths

### 4. It gives you typed durable state beyond files

Files matter, but they are not the whole story.

CK keeps durable state in typed surfaces such as:

- memory
- proof bundles
- traces
- outcomes
- checkpoints
- review packets

That makes the work resumable and auditable in a way most hosts do not provide natively.

### 5. It adds real trust-boundary behavior

ControlKeel explicitly models:

- trusted vs mixed vs untrusted content
- hidden instruction channels
- skill and plugin trust boundaries
- high-impact action escalation
- destructive shell tripwires

A host may expose tools. That does not mean it gives you a real governance model for those tools.

### 6. It is built for project rescue too

Even if another agent or tool already touched the repo, CK still helps by:

- bootstrapping the project
- surfacing findings
- reconstructing context
- validating risky content
- restoring review and proof flow

That rescue path is one of the most practically important differences.

## What hosts or agents usually do not provide

A host may provide:

- a chat UI
- tool calling
- file editing
- shell execution
- browser automation
- a native review UI
- its own memory or session history

But hosts usually do **not** provide the full ControlKeel layer in a portable, cross-host way.

What they often do not provide, or do not provide consistently, is:

- a portable governance loop across multiple agent hosts
- a typed support model that says what is truly supported and how
- repo-local proof bundles
- cross-host policy and findings continuity
- stable, explicit trust-boundary modeling
- strong destructive-op validation before execution
- budget governance and provider brokerage independent of one host
- typed resume packets and workspace reacquisition context
- a clean distinction between attach-native, runtime-export, provider-only, and fallback-governance modes

This is the key point:

**The host is usually optimized for using an agent. ControlKeel is optimized for governing agent work.**

## Why this matters even when the host is good

Even strong hosts still optimize for their own environment.

That leaves gaps if you care about:

- moving across hosts
- governing several kinds of agents
- keeping the same delivery rules in every repo
- preserving evidence and review state outside one vendor UI
- attaching new hosts without rewriting your entire workflow

ControlKeel gives you that portability and governance continuity.

## Who ControlKeel is for

The clearest users are:

- serious solo builders shipping with agents
- tiny agent-heavy teams
- people using more than one host or agent product
- teams that need reviewability, proofs, and release discipline
- teams working in higher-risk domains
- people who want a rescue path when another tool already changed the repo

It is especially useful when the problem is no longer “can the model write code?” and is now:

- “can we trust what just happened?”
- “can we review this?”
- “can we prove this?”
- “can we resume this later?”
- “can we ship this safely?”

## Who the customer is

There are a few customer layers:

- **Primary user**: the developer or operator running agent-heavy work in a real repo
- **Team buyer**: the small team lead who wants consistency, approvals, and proof without building an internal governance stack from scratch
- **Higher-trust buyer**: teams in domains where approval, evidence, or constraints matter more than raw speed

The product is strongest today for serious individuals and small teams rather than “big centralized enterprise admin suite first.”

## Why someone would choose ControlKeel instead of only using a host

Because hosts are excellent at being hosts, but they are not neutral control planes.

Choose ControlKeel when you want:

- the same governance loop across different hosts
- a clear support contract
- structured context and validation
- proofs and findings that live with the governed project
- safer behavior around risky execution
- runtime/provider flexibility
- a way to bring messy agent work back into a reviewable state

## The simplest mental model

If the coding agent is the engine, ControlKeel is the flight control layer.

If the host is the cockpit, ControlKeel is the system making sure the aircraft is still inside the approved envelope.

If the model writes the code, ControlKeel governs the path from idea to safe delivery.

## ControlKeel as the governance layer for company context graphs

The industry is moving from giving agents access to tools (connectors, MCP servers, integrations) to building **company brains** — synthesized, conflict-resolved, continuously updated representations of organizational context. ControlKeel provides the governance foundation for this next phase.

### From retrieval to synthesis

Current agent systems focus on retrieval: when the agent needs context, it searches Slack, Google Drive, CRM, and other tools. This is a scavenger hunt that starts from zero every time. ControlKeel's `ck_context_pack` and typed memory provide **synthesized understanding** — a persistent, accumulated model of your project's context that agents read from instead of searching for.

### Filesystem-based context delivery

The most robust way to deliver company context to agents is through the filesystem. Every agent already knows how to read files. ControlKeel's workspace snapshots, `.agents/skills`, `.opencode/`, `.codex/`, and other repo-native assets deliver governed context as structured files that any agent can read without custom integration. When you switch from OpenCode to Claude Code to Codex, the context persists because it lives in your repository, not in a specific agent runtime.

### Cross-agent context compatibility

A company brain shouldn't be locked into one agent vendor. ControlKeel's cross-host consistency ensures that the same governed context, typed memory, and proof bundles work across OpenCode, Codex, Claude Code, Copilot, Cursor, Windsurf, and dozens of other hosts. Your accumulated understanding survives host switches and tool changes.

### Conflict resolution and source authority

Company data constantly contradicts itself — Slack says one deadline, Linear says another, a meeting recording says a third. ControlKeel's findings system and validation gates provide the conflict-resolution framework: when sources disagree, CK's deterministic validation and policy enforcement determine what's authoritative. Proof bundles track which decisions were made, which sources were consulted, and why.

### Identity and continuity across sessions

The same person appears as "Lisa Chen" in email, "@lisa" in Slack, and "L. Chen" in calendar invites. ControlKeel's session/task graph, agent binding, and typed memory unify identity across these fragmented representations. Resume packets and task continuity mean work survives not just across sessions, but across hosts and team members.

### Accumulated understanding that compounds

A context graph gets better every day it runs. Day one, it knows a little. Day thirty, it has absorbed thousands of decisions, resolved hundreds of conflicts, and built a model of how your team actually works. ControlKeel's typed memory, proof bundles, and experience index capture this accumulated understanding. Every new decision, finding, and proof event makes the existing context more valuable. You can't fast-forward six months of accumulated understanding — but you can start building it today.

### The governance layer for company brains

ControlKeel is not itself a context graph or company brain. It's the governance layer that makes context graphs trustworthy, auditable, and portable. When you build a system that synthesizes company context from Slack, Notion, GitHub, and other tools, ControlKeel provides:

- **Validation**: Ensure synthesized context meets security and compliance standards before agents use it
- **Proof bundles**: Immutable records of what context was used, what decisions were made, and why
- **Review gates**: Human approval workflows for high-impact context changes or agent decisions
- **Cross-host portability**: The same governed context works across any agent host
- **Budget and cost control**: Track spend and resource usage across all context-aware agents
- **Typed memory**: Persistent, citable records of context synthesis decisions that compound over time

The industry gave agents access in 2025. In 2026, we're building company brains. ControlKeel provides the governance foundation that makes those brains safe, auditable, and portable.

## The practical takeaway

If you only need code generation, you may not need ControlKeel.

If you need:

- governed execution
- validation before risky actions
- cross-host consistency
- findings, approvals, and proofs
- resumable task state
- delivery and ship discipline
- governance for company context graphs and synthesized understanding

then that is exactly what ControlKeel is for.
