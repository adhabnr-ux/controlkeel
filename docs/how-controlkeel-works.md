# How ControlKeel Works

This document explains **how ControlKeel works in detail**, not just what it is.

It is meant for readers who want the exact operating model:

- how CK turns user intent into governed execution
- how CK interacts with hosts and agents
- how CK exposes context and validation
- how CK records review state, findings, and proofs
- how CK differs from a host, IDE, or raw MCP server

If you want the shorter product explanation first, read [explaining-controlkeel.md](explaining-controlkeel.md).

## The core idea

ControlKeel is a **control plane above generators**.

That means:

- the coding agent still writes code, plans, shell commands, or tool calls
- the host still provides the primary user interface
- the repo still contains the code and git state
- but CK manages the **governed delivery loop** around that work

CK does this by adding five things most agent hosts do not provide as one portable system:

1. a structured understanding of the work boundary
2. a governed tool and context surface for agents
3. validation and review gates around risky work
4. durable evidence and resumable task state
5. a typed integration model across many hosts and runtimes

It now also has a first-class **defensive security workflow** layered on top of that same chassis. CK does not create a separate security product surface. It reuses the same sessions, tasks, findings, proofs, validation, delegation, and release gates, but gives `security` sessions explicit phase structure and dual-use controls.

## The full lifecycle

In current product terms, CK runs this lifecycle:

1. intent intake
2. execution brief compilation
3. execution posture compilation
4. runtime recommendation compilation
5. task graph and routing
6. validation and findings
7. proof capture
8. ship metrics
9. comparative benchmark evidence
10. autonomy and improvement loop summaries

For `security` domain work, the lifecycle becomes:

1. discovery
2. triage
3. reproduction
4. patch
5. validation
6. disclosure and release readiness

That lifecycle is not just a pitch. It maps directly to the code-backed architecture and the main product surfaces.

## Step 1: intent intake

CK starts by turning user-supplied information into a normalized input model.

The important idea is that ControlKeel is **occupation-first and delivery-first**, not “pick a compliance acronym first.”

It asks:

- what kind of work is this?
- what domain does it belong to?
- what constraints matter?
- what data is involved?
- what delivery risk does this imply?

That is surfaced through the intent layer. The public entry point is [intent.ex](lib/controlkeel/intent.ex).

The intent layer does not directly run agents. It compiles meaning:

- supported domain packs
- occupation profiles
- interview questions
- preflight context
- execution brief
- execution posture
- runtime recommendation
- boundary summary

This is important because CK does not start from “what tool can the model call?” It starts from “what kind of delivery boundary are we in?”

## Step 2: execution brief compilation

The execution brief is CK’s normalized summary of the work.

It is the first stage where vague human input becomes a governed artifact. The brief describes things like:

- risk tier
- likely domain pack
- constraints
- compliance expectations
- launch context
- open questions

The brief is later consumed by:

- Mission Control
- boundary summaries
- execution posture
- runtime recommendation
- task planning
- routing

This matters because CK keeps the **boundary** explicit instead of letting it stay hidden in a prompt.

For security work, the execution brief also carries:

- the `security` domain pack
- a defender-oriented mission template
- the default `cyber_access_mode`
- disclosure redaction defaults
- explicit release gating for vulnerability cases

## Step 3: execution posture compilation

Execution posture is how CK decides **what kind of execution surface is appropriate**.

This is not the same thing as “which agent should I use?”

It answers:

- should the work begin in read-only discovery?
- should durable state live in files, or in typed proof/memory/traces?
- should the work prefer typed/code-mode runtime over raw shell?
- when should shell still be allowed?
- how much approval pressure should exist?

The current execution posture model is explicitly built around these principles:

- use the read-only virtual workspace first for discovery
- keep durable state in typed surfaces such as memory, proofs, traces, and outcomes
- prefer typed or code-mode execution for large API or MCP-style tool surfaces
- keep shell as the fallback mutation surface
- escalate approval pressure as work moves toward broad or destructive authority

For memory specifically, CK treats two different problems separately:

- retrieval: finding the most relevant prior records, proofs, transcript events, and resume context
- integration: deciding how those retrieved artifacts should actually change the current reasoning

That distinction matters because CK does not present memory as perfect recall. It can return ranked memory hits and portable typed state, but the active agent still has to reconcile those hits with the current task, recent transcript tail, and current validation state.

When a team wants durable intent to persist beyond a single turn, CK prefers explicit goal records over hidden prompt mutation. Goals can live in governed typed memory as first-class records, which means the agent can list, cite, and update them later without pretending that the host has magical passive recall.

CK also treats host-managed file memory as a companion surface rather than the governed source of truth. Repo-visible instruction files, sandbox-local notes, or mounted memory directories can still be useful for fast local recall inside a specific host. But CK keeps durable governed state in typed memory records, proofs, traces, workspace snapshots, and resume packets so continuity survives host switches and stays reviewable.

This is one of CK’s biggest philosophical differences from many hosts:

- hosts often begin from “the model has tools”
- CK begins from “the work has a posture and a boundary”

## Step 4: runtime recommendation compilation

After execution posture, CK derives a **runtime recommendation**.

This is where CK moves from abstract posture to a real path such as:

- use an attach-first host with stronger review surfaces
- use a headless runtime export
- use a configured or attached runtime path already present in the workspace

The recommendation is not generic. It is grounded in:

- the brief
- the posture
- the typed integration catalog
- currently attached agents
- runtime bundles already exported into the workspace
- provider/runtime signals

This means CK can say something much stronger than “use a sandbox.”

It can say:

- this work is review-heavy, so use an attach-first host
- this work is API-heavy and code-mode friendly, so a typed runtime is the better fit
- this workspace already has a usable attached or configured surface, so prefer that

This is a practical difference from many systems that only reason in the abstract.

CK now also derives a harness policy layer alongside that recommendation.

At this point it helps to make one distinction explicit:

- CK is the harness and control plane
- the sandbox or runtime is the execution environment

Those are related, but they are not the same product surface.

When CK recommends an attach-first host or a `headless_runtime` export, it is choosing an execution path. It is not claiming that CK itself is a microVM substrate or that every runtime is interchangeable at the filesystem level. The point is narrower: CK keeps the governed loop and its durable state outside any single runtime instance.

That policy makes the control-plane assumptions explicit:

- read-only discovery tools can be parallelized
- mutations stay serialized
- tool execution is expected to happen inside the main loop, not as an untracked afterthought
- durable memory should stay in CK-controlled typed surfaces, not disappear into opaque provider-managed state
- memory retrieval and memory integration are separate governed steps, not a single magical recall surface
- high-confidence claims should prefer citable memory and proof-backed context
- context compaction should run hierarchically, cheapest first
- major error classes need named in-loop recovery paths
- delegated mutation should prefer isolated worktrees or equivalent governed runtimes
- network and other high-impact egress should default to deny and open only through explicit task-scoped reviewed allowlists

### Event-sourced harness posture

A useful agent harness lesson is that the durable record should look like an append-only event log, while stateful views are derived from that log. CK already stores governed session events, findings, reviews, proofs, invocations, memory, and outcomes as typed records; the design principle is to make those records the source of audit truth instead of relying on opaque host state.

For CK, the practical pattern is:

- **append first, project second**: capture facts as typed events or records, then derive dashboards, loop status, failure clusters, and readiness views from them
- **reducers are pure projections**: summaries such as loop health, memory quality, or release readiness should be recomputable from stored records where possible
- **side effects happen after reviewable facts**: expensive or high-impact work should be triggered by governed state transitions, not by hidden callbacks that leave no durable trace
- **idempotency and circuit breakers are first-class**: repeated tool calls, retries, and fast event loops need dedupe keys, rate budgets, and explicit pause/reset paths
- **provenance travels with the event**: actor, source type, trust level, capability grant, workspace, and task scope should stay attached to evidence
- **dynamic code is extension material, not authority**: an event or trace that contains processor source should be reviewed like a plugin/skill bundle before it can change behavior

This keeps CK compatible with event-stream-style agent systems without turning CK itself into an unauthenticated public event bus. External streams can be imported as evidence, but the governed control plane still decides what may execute, persist, or promote.

This is important because “posture” and “policy” are different things.

Posture answers:

- which surfaces should this session prefer?

Policy answers:

- how should the loop behave when it is under pressure?
- what can run concurrently?
- who owns durable memory, and how portable is it across hosts?
- what gets compacted first?
- what recovery path is expected when things fail?
- what isolation standard should delegated work meet?

## Step 5: task graph and routing

Once the work is understood, CK turns it into governed task state.

This includes:

- sessions
- tasks
- task status
- task graph state
- decomposition summaries
- review state
- checkpoints
- resume packets
- routing hints

This is where ControlKeel moves from “understanding the work” to “operating the work.”

The practical effect is:

- work becomes resumable
- progress becomes inspectable
- review can happen against task state, not just raw diffs
- agents can reacquire context without pretending they remember everything
- recursive or delegated slices can be understood as governed nodes, not invisible prompt tricks

Mission Control is the UI expression of this layer, but the underlying state also feeds:

- CLI flows
- MCP tools
- hosted protocol access
- agent execution and delegation

## Step 6: governed context for agents

This is one of the most important parts of the system.

CK does not primarily help agents by pasting more context into prompts. It gives them **governed tools and typed context surfaces**.

A related practical point is tool scalability: large API surfaces do not fit as "one tool per endpoint" inside a context window. CK therefore biases toward **progressive discovery** instead of tool dumps. Three common strategies (which can be combined) are:

- **CLI introspection**: the agent uses `--help` and subcommand discovery to find the right action (requires shell access).
- **Tool search**: load only a small subset of tools by query or intent, rather than registering everything at once.
- **Code-mode / typed runtime**: expose a compact typed interface (SDK/types), let the agent generate a small script for the specific action, and execute it inside a governed default-deny sandbox.

The most important one is `ck_context`.

`ck_context` returns session-bound context such as:

- findings summary
- budget summary
- boundary summary
- current task
- planning context
- proof summary
- memory hits
- resume packet
- workspace snapshot
- workspace cache key
- context reacquisition signals
- recent transcript events
- transcript summary
- provider status

This makes the agent’s context:

- bounded
- session-aware
- workspace-aware
- resumable
- explicit

That is very different from letting an agent infer the state of the world from raw chat history or from repeated shell exploration alone.

CK now also derives a **task augmentation** artifact inside `ck_context`. It is not a separate execution engine. It is a derived contextual brief built from:

- the current task and session objective
- workspace context and repo instruction files
- recent hotspots and large-file signals
- active findings
- boundary constraints

The point is to make vague work more executable before the main run loop starts, without stuffing the entire repo into model context.

### First-orientation search loop

Agentic search should optimize the first useful read, not just raw search latency. CK's default discovery loop should stay explicit and bounded:

1. call `ck_context` to recover the task boundary, findings, budget, and `task_augmentation` hints
2. inspect likely paths and high-signal search terms before broad exploration
3. use `ck_fs_find` for path candidates and `ck_fs_grep` for content candidates
4. prefer source-ish, shallow, high-signal results before tests, vendor, or build artifacts
5. read only the top candidates with `ck_fs_read`, then widen deliberately if the first orientation was wrong
6. use `ck_context_pack` when prior memory, proof, or review history may change the next step

This keeps retrieval as an attributed evidence surface. CK can rank and summarize candidates, but the agent still has to reconcile those candidates with the active task, findings, and proof state.

## How CK keeps context grounded

CK resolves workspace context from governed state, not only from process-local assumptions.

For example:

- runtime context can attach a `project_root`
- workspace resolution can look at the governed session binding
- MCP callers can provide a `project_root` hint
- but governed session/runtime state wins when CK already knows the right workspace

That matters because the same governed session should not appear differently depending on which host or working directory touched it.

## Step 7: validation before risky action

CK’s validation loop is centered on `ck_validate`.

This is one of the core product surfaces because it is where proposed work is checked before it becomes action.

`ck_validate` accepts:

- code
- config
- shell
- text

It also accepts structured trust-boundary metadata such as:

- `source_type`
- `trust_level`
- `intended_use`
- `requested_capabilities`
- `session_id`
- `task_id`
- `domain_pack`

Internally, validation is layered.

### Layer 1: FastPath

FastPath is the first deterministic validation layer.

It combines:

- pattern rules
- entropy checks
- budget findings
- trust-boundary findings
- destructive shell tripwires

This is where CK catches things like:

- secrets
- obvious injection patterns
- domain-specific policy problems
- unsafe trust-boundary crossings
- broad destructive shell operations

Recent destructive-shell protection is a good example of how CK governs execution rather than only reviewing code after the fact.

Repo-wide commands such as:

- `git checkout -- .`
- `git restore .`
- `git reset --hard`
- `git clean -fd`
- broad `rm -rf`

are blocked with recovery guidance, checkpoint hints, and rollback hints.

### Layer 2: Semgrep

If the content looks code-like and Semgrep is available, CK adds Semgrep findings to the decision.

### Layer 3: advisory review

If a provider is configured, CK can add an advisory review layer on top of deterministic findings.

That layer is explicit, not magical.

The result always states whether advisory ran or was skipped.

### Validation result

The final result includes:

- allowed or blocked decision
- summary
- normalized findings
- optional fix prompts
- advisory status

This is the public contract that hosts and agents see.

## Why validation is central to CK

Many agent systems assume:

- the model can reason well enough
- the host permissions are enough
- the human can catch issues later

CK does not assume that.

Instead it treats validation as a **first-class control surface**.

That is why validation is exposed consistently through:

- local CLI flows
- local MCP
- hosted MCP
- A2A-adjacent interop
- web surfaces

## Intentional friction, not frictionless shipping

One of CK's design assumptions is that **some friction is good**.

This is not accidental product roughness. It is part of the control-plane model.

CK is not trying to optimize every session toward "ship without friction." It is trying to keep the places where human judgment matters from disappearing behind fast agent output.

A practical reason is review capacity. Agents can generate diffs faster than humans can safely review them, which creates pressure to rubber-stamp large changes. CK treats that as a failure mode of the delivery system, not as a personal discipline problem.

### The psychology of speed addiction

Armen and Christina describe a pattern many teams experience: AI tools start as fun and give engineers free time, but quickly become pressure to ship faster. The baseline expectation shifts from "agents are optional helpers" to "everyone must use agents to keep up."

This creates a trap:
- **Addictive loop**: You never know if the next prompt will make your product work or bring it crashing down, so you keep prompting
- **False efficiency**: You produce output fast and feel productive, but lose time to actually think and design
- **Review capacity mismatch**: Every engineer now has much more producing power than reviewing power, leading to skipped or rubber-stamped reviews
- **Expanded participants**: Marketing people, former CEOs, and others ship code, but responsibility still rests with the engineering team

CK's governance layer is designed to counteract this by making human judgment explicit and unavoidable at the right boundaries. The goal is not to eliminate speed—the goal is to keep speed from becoming a substitute for thinking.

This is the steering layer of the governed engineering game loop: humans design the mission, constraints, taste, budget, and stopping rules; agents get bounded attempts; CK turns the run into risk, cost, drift, proof, and approval signals.

Friction is also steering. Without deliberate friction at the right boundaries (permissions, schema/migration changes, irreversible operations, release posture), teams lose the moments where experience should re-activate. As Armen puts it, "without friction there's no steering."

That shows up in the current implementation in a few concrete ways:

- architecture and release-oriented work is explicitly decomposed into review-heavy or `human_gate` nodes instead of being treated like ordinary implementation slices
- task plans carry rollback boundaries and validation gates, especially as risk rises
- Mission Control surfaces human gate hints on findings instead of pretending every issue should be auto-fixed and silently resumed
- `ck_validate` models trust boundary, intended use, and requested capabilities so risky actions can be treated differently from ordinary text or code review

The practical point is simple:

- speed is useful when the work is narrow and reversible
- friction is useful when the work changes architecture, release posture, permissions, destructive authority, or rollback safety

That is also why CK begins critical work with architecture and policy constraints before code generation, and why higher-risk paths keep review and proof pressure close to the loop.

### Human bottlenecks as a feature

A counterintuitive insight from Mario's experience is that **human bottlenecks are a feature, not a bug**. Humans are slow, failible beings, but that slowness limits how many errors ("boooos") they can add to a codebase per day. Humans also feel pain—when code becomes too painful to work with, humans quit, blame others, or band together to refactor it.

Agents don't feel pain. They will happily keep adding errors to a codebase indefinitely. This is why "100% built by agents" products often suck—the error compounding has no natural stopping point.

CK's design accepts this reality:
- Human review capacity is a constraint, not a problem to eliminate
- The goal is to make human review effective, not to remove it
- Scoped tasks and evaluation functions keep agent work reviewable
- Critical code requires human line-by-line review; non-critical code can use agents

### Specs as programs

Mario's observation that "a sufficiently detailed spec is a program" is relevant to CK's alignment workflow. When you leave blanks in a spec, the model fills them with garbage learned from internet training data (90% of code on the internet is "our old garbage").

CK's alignment workflow (`align` skill) is designed to avoid this by:
- Reaching shared understanding of what, why, which layers, success criteria, and unknowns before any planning or code
- Making blanks explicit rather than letting the model silently fill them
- Feeding the aligned result into plan-slice or review workflows

The point is not to write perfect specs. The point is to be honest about what's specified and what's being left to the model's internet-trained priors.

### Scarce vs abundant resources

Ryan Leopo's experience building software exclusively with agents for nine months reveals a shift in what's scarce and what's abundant:

**Abundant:**
- Code is free to produce, refactor, and delete
- Implementation is no longer the scarce resource
- Each engineer has access to 5, 50, or 5,000 engineers worth of capacity 24/7
- Large-scale refactoring is free (fire off 15 agents to drive migrations to completion)

**Scarce:**
- Human time
- Human and model attention
- Model context window

In a world where code is abundant, the stack ranking changes. Previously, things were P0 or P2, and P3s never got done. Now, all those P3s get kicked off immediately—maybe 4x in parallel—pick one that solves the problem, and ship it.

CK's governance is designed around this reality:
- Optimize for scarce human attention: make human judgment explicit and unavoidable at the right boundaries
- Manage context efficiently: progressive discovery, compact repo-local instructions, event-driven hooks
- Treat code as a means, not an end: the important thing is not the code but the prompt, guardrails, and process that got you there

## Agent-legible repos

CK also assumes that the repository itself becomes part of the agent execution surface.

### Model rot and reference shapes

Frontier models are trained on a snapshot of the world. Fast-moving ecosystems can drift faster than training cycles, which shows up as "model rot": outdated APIs, invented patterns, and integrations that are technically plausible but wrong.

CK does not try to solve this by assuming a bigger base model is always enough. The practical mitigation is to give agents **fresh, curated, repo-visible context**:

- up-to-date markdown docs that the agent can load on demand
- thin reference implementations that represent the *shape* of a correct integration without requiring a full production app

Danilo's experience with the PostHog Wizard reinforces this pattern: with context windows being what they are, "you can't beat just shoving a bunch of markdown files into the context and patching the holes." The Wizard uses fresh hot markdown from posthog.com and lets the agent select what it needs based on the framework and language being integrated.

Those reference implementations are especially useful when you want consistency at scale: they constrain improvisation by example without overconstraining the agent's search space.

### Model airplanes

Danilo calls these thin reference implementations "model airplanes" - projects that have the correct shape of an integration without being full production applications. For example, auth might work for anything (you can put whatever you want in the password field), but the UI is auth-shaped. This makes them:

- **More token efficient**: Not a full production app, just the shape
- **Consistent**: Agents learn the correct pattern once and apply it consistently
- **Maintainable**: Easier to update than full reference apps when patterns change

By providing model airplanes, the agent knows "oh cool, when auth shows up, this is a great place to put login and identity tracking" and can complete the integration consistently every time. This limits the "sorcerer's apprentice" problem where agents might find 15,000 different ways to do the same integration, creating an impossible support burden.

### Breadcrumbing

Danilo's Wizard uses a breadcrumbing pattern to limit improvisation and prevent agents from taking weird paths through the problem space. Instead of telling the agent upfront exactly what to do ("do a PostHog integration"), the Wizard:

1. **Discovery phase**: "Where are the files with interesting business value? Find something that looks like a login or Stripe interface or churn indicator"
2. **Event identification**: "What are the interesting events in those files? Don't write code yet, just think about what events we might want to track"
3. **Implementation**: Only after events are identified and documented does it start implementing PostHog

This works because "business stuff casts a huge shadow in code" - you can reliably detect files that would be responsive to business impact. By sequencing the information this way, the agent makes thoughtful decisions about what to track before writing any code.

CK's planning and task decomposition already follows a similar pattern: understand the workspace and business context before prescribing implementation details.

### Post-run agent interrogation

A critical insight from Danilo's experience is that "human error is a big deal" and "you have to ask to find out." The Wizard runs post-run interrogation at the end of every run, asking the agent a simple question: "What could we have done better to set you up for success in this run?"

This cheap inference-time interrogation revealed issues that would otherwise have gone unnoticed:
- Contradictory tool instructions
- Missing tools (MCP didn't have the tool the agent was told to use)
- Wrong language instructions (giving JavaScript instructions for a Python project)

CK's session and task state already captures what happened, but adding explicit post-run interrogation could surface configuration errors, missing capabilities, or contradictory directives that operators might miss.

### Prose-first governance

Danilo notes that the PostHog Wizard is "90% markdown files, 8% tools for delivering and processing markdown files, and the rest is agent harness stuff." This reflects a broader insight: plain text prose appreciates in value as models improve, while code depreciates.

When you write great prose today and tomorrow a better model drops, it can take that prose and do even more with it. Code, by contrast, is a depreciating asset - the code you write today has the exact same value tomorrow, and might even decline as tech debt accumulates.

CK's emphasis on plain text artifacts (briefs, plans, skills, checklists, runbooks) as first-class governance inputs aligns with this pattern. High-quality prose becomes more valuable as models improve because better models can apply the same durable guidance with less scaffolding.

### Modularization of code flow

Armen and Christina emphasize that agent-legible codebases require not just modular components, but also modularized code flow. Clearly defined main points between steps (e.g., "user message → agent loop → output") make it obvious where the agent should add logic and where it shouldn't.

Between these clear boundaries, agents tend to add "fuzz"—parsing between types, adding things to state that shouldn't be there, creating behaviors you didn't intend. By making the code flow explicit and stepwise, you reduce the surface area where agents can introduce unexpected behavior.

### Follow known patterns

Christina's advice is to lean into reinforcement learning rather than fight it. Agents perform better when code follows established patterns:
- Simple core with complexity pushed to abstraction layers
- No hidden magic or implicit behavior
- Consistent interfaces and patterns across the codebase

This is especially important for libraries vs products. Agents excel at libraries (clearly defined problems, tight constraints, simple core) but struggle with products (intertwined concerns, can't fit global structure in context window).

### Mechanical enforcement patterns

To make agent-legible codebases work in practice, Armen and Christina recommend mechanical enforcement via linting rules:
- **No bare catch blocks**: Force explicit error handling
- **One SQL query interface**: Single place for SQL so agents don't miss breaking changes
- **One primitive component library**: Consistent UI styling and behavior, no raw input boxes
- **No dynamic imports**: Predictable dependency graph
- **Unique function names**: Better token efficiency when agents grep for features
- **Erasable syntax/TypeScript mode**: One source of truth between code and compiler, no transpilation confusion

These patterns are not about style—they're about making the codebase predictable and legible for both humans and agents. When an agent can find what it needs with one grep result instead of ten, it's less likely to introduce bugs.

### Lints as prompts

Ryan emphasizes that lint error messages should provide actual remediation steps to the model, not just failures. A lint saying "awaiting in loop" or "unknown type here" is not enough. The lint should say: "no no no you shouldn't have an unknown here at all because we parse don't validate at the edge."

This turns every lint or test failure into a prompt that guides the agent toward the correct behavior. The pattern is:
- Lint detects a violation
- Lint message explains why it's wrong and what to do instead
- Agent self-heals based on that guidance
- Next time, the agent learns the pattern

This is particularly powerful for things that humans are unreliable at reviewing—like ensuring every network call has timeouts and retries. Write the lint once, let the agents migrate the entire codebase to comply, and the problem is solved durably.

### Source code tests

Ryan recommends writing tests about the source code itself, separate from lints, to adapt the codebase to the harness. Since context is limited, you can write a test that limits files to no longer than 350 lines. This is "engineering to be context efficient"—squeezing more juice out of the model capability by adapting the codebase to how the harness works.

Other examples of source code tests:
- Asserting package privacy and dependency edges between layers
- Ensuring Zod schemas are deduplicated (single canonical implementation)
- Verifying use of shared utilities instead of local duplicates
- Checking that async helpers follow a single pattern

These tests shake out bad behavior (agents optimizing for local coherence rather than using shared utilities) so humans don't get distracted paying attention to it in reviews.

### Code as disposable artifact

Ryan proposes a mental model: **LLM as fuzzy compiler**. Code is a compiled artifact of the spec, and all the context in the codebase (skills, docs, lints, tests) is effectively constraints and optimization passes on which code is acceptable to build.

This is similar to how LLVM does static analysis and optimization passes when compiling Rust code. Swapping out one model for another is like changing your code generation backend from LLVM to Cranelift—you'd expect all the rules around what acceptable Rust code looks like to produce valid sound machine code, regardless of the generation process.

The same applies to LLMs: the structure around the code should limit how it's written to things that are acceptable, regardless of which model generates it. This is why CK focuses on:
- Stable context contracts
- Versioned tool definitions
- Durable governance (findings, proofs, reviews)
- Provider portability

The code itself is disposable; the governance layer is what matters.

That does **not** mean CK currently enforces a single repo style. It means the product is built around the idea that agents do better when the repo stays reviewable, scoped, and legible.

Current CK behavior already nudges in that direction:

- intent and planning prefer small PR slices and rollback-safe delivery
- task decomposition separates architecture, feature, and release tracks instead of flattening them into one giant execution stream
- validation and findings preserve explicit boundary metadata rather than hiding risk inside natural-language prompts

So for teams using CK seriously, “agent-legible” usually means:

A practical harness trick is to treat guardrails as *just-in-time prompts* rather than always-loaded policy walls. Lints, tests (including tests about code shape), and reviewer agents can surface the right constraint at the moment the agent tries to finalize work. This keeps the initial context small, while still enforcing non-functional requirements consistently across the repo.

- keep work in narrow slices the human can still review
- keep architecture and release boundaries explicit
- preserve obvious rollback paths where mutation is involved
- do not treat generated volume as proof that the underlying design is getting clearer

CK's role here is not to magically remove entropy after the fact. It is to keep the operator boundary visible while the agent loop accelerates.

## Step 8: findings and review gates

If validation or governance identifies a problem, CK turns it into a governed finding.

A finding is not just a warning string. It has state.

Typical properties include:

- rule id
- category
- severity
- decision
- status
- human gate hints
- task/session linkage
- metadata

This lets CK treat review as part of the delivery system instead of as detached commentary.

For plan reviews, CK can also carry alignment context that did not come from the codebase:

- business or product constraints gathered from humans
- design, support, security, or operations context
- prior team decisions that should shape implementation
- which roles were consulted before execution starts

That matters because the best review packet is not only "here is the code or plan." It is also "here is the non-code context that should prevent the team from building the wrong thing quickly."

Review state can then be:

- opened
- blocked
- escalated
- approved
- denied
- tracked through review packets and browser review flows

This is how CK creates a bridge between:

- machine-detected issues
- human approval workflows
- later evidence and proof state

## Step 9: proof bundles and durable evidence

Once work progresses or completes, CK captures proof.

Proof bundles are important because they answer:

- what happened?
- what was reviewed?
- what was validated?
- what findings existed?
- what was the rollback guidance?
- was the task actually deploy-ready?

Proof is one of the strongest differences between CK and many hosts.

Hosts may show chat history or diffs.

CK stores:

- proof bundles
- resume packets
- transcript summaries
- workspace snapshots
- memory records
- outcomes
- checkpoints

That is the practical restartability story in CK.

If a runtime dies, the important durable record is not just whatever happened to be left in that runtime's local filesystem. The recoverable control-plane record lives in:

- task and session state
- findings and review state
- proof bundles
- recent transcript events and transcript summaries
- resume packets, checkpoints, and typed memory

The local filesystem inside a sandbox or runtime can still be important, especially for generated files or repo mutations. But CK treats that as one execution surface among others, not as the only place the trajectory survives. This is also why CK avoids treating hidden provider memory as the durable source of truth.

This lets the system remain useful after the original chat session is gone.

## Step 10: ship metrics and benchmarks

CK does not stop at “the agent finished.”

It tracks:

- ship readiness
- deploy-ready proof state
- outcome metrics
- benchmark evidence
- comparative runs

This is where CK shifts from “agent assistant” territory into “delivery control plane” territory.

The final question is not only:

- did the agent write code?

It is also:

- is this work ready to ship?
- what evidence supports that?
- how did this compare to other runs?

## The host model

A big part of how CK works is its host model.

CK does not pretend every host is the same.

Instead it uses a typed integration catalog with support classes such as:

- `attach_client`
- `headless_runtime`
- `framework_adapter`
- `provider_only`
- `alias`
- `unverified`

Each row also models things such as:

- how the agent uses CK
- how CK runs the agent
- execution support
- review experience
- runtime transport
- auth owner
- package outputs
- confidence level

This matters because “supports host X” is meaningless unless you say **how**.

CK’s model is explicit about whether support comes from:

- native attach
- plugin
- hooks
- rules
- workflows
- hosted MCP
- A2A
- runtime export
- provider-only path
- fallback governance

## How agents use CK

The “agent uses CK” direction includes surfaces like:

- local MCP
- hosted MCP
- A2A
- plugins
- native skills
- rules
- workflows
- hooks

This means the host agent can call back into CK for:

- context
- validation
- findings
- budgeting
- routing
- delegation
- memory
- proof-aware continuity

This is what makes CK usable **by agents**, not just around them.

## How CK runs agents

The reverse direction is equally important.

CK can operate agents through:

- `embedded`
- `handoff`
- `runtime`
- `none`

The practical meanings are:

- `embedded`: CK can launch a locally verifiable command/runtime path itself
- `handoff`: CK prepares the governed package and hands off to the host
- `runtime`: CK talks to a headless or remote runtime
- `none`: the agent may use CK, but CK does not drive it directly

This is the other half of the system architecture:

- agents use CK
- CK can also route or execute through agents where truthful

## Provider brokerage

CK also resolves provider access independently of any one host.

Provider resolution can come from:

1. attached agent bridge
2. workspace or service-account profile
3. user default profile
4. project override
5. local Ollama
6. heuristic fallback

This means CK can still function when:

- the host has no documented bridge
- the host uses its own internal auth model
- the user wants CK-owned provider control
- the user wants a local or OpenAI-compatible backend
- no provider is available and heuristic mode is required

This independence is important because governance and delivery should not disappear just because one host’s provider path is opaque.

## Hosted and local protocol surfaces

CK exposes both local and hosted protocol layers.

### Local stdio MCP

This is the normal repo-local path for attached clients.

### Hosted MCP

This is for service-account and remote usage.

Hosted MCP exposes a governed subset of tools under scoped authorization.

### Minimal A2A

This gives agent-card discovery and narrow message dispatch for external agent systems.

The important thing is that these transports all expose the **same governed model**, not entirely different products.

## Enterprise gateway, catalog, and lineage

If you look at CK from an enterprise rollout perspective, three existing behaviors matter a lot:

1. one governed gateway layer for model and compatible API access
2. one typed catalog/discovery layer for host and protocol surfaces
3. one lineage model for governed work state

### One governed gateway layer

CK already centralizes several things that large organizations otherwise rebuild team by team:

- provider resolution and fallback
- governed OpenAI-compatible and Anthropic-compatible proxy access
- explicit budget and spend tracking

So the current CK story is already close to an enterprise AI gateway, but with a governance-first emphasis rather than only a traffic-routing emphasis.

### One typed catalog/discovery layer

CK also already has a catalog model for agent and runtime connectivity:

- the typed integration catalog
- `/skills` and `GET /api/v1/skills/targets`
- hosted MCP discovery metadata
- minimal A2A plus published agent card data
- optional ACP registry enrichment

This matters because CK does not force every team to describe agent connectivity from scratch. It keeps one typed, reviewable record of how a host or runtime uses CK, how CK can run it, what artifacts it installs, and what confidence/support level the surface really has.

### One lineage model

CK does not currently market a separate “use case registry” product surface by that exact name.

What it does have today is a governed lineage model that already connects:

- workspace
- session
- task
- review
- proof
- task-run and audit-export metadata

That gives CK a practical enterprise answer to questions like:

- which governed workspace does this action belong to?
- which task or review is affected?
- what proof or audit evidence exists?
- which service account is allowed to touch it?

So the current product truth is not “CK ships every registry in the abstract.” The truthful claim is that CK already combines gateway control, typed discovery, and governed lineage into one control-plane model.

## Why CK is not “just an MCP server”

Because MCP is only one transport layer.

CK also includes:

- project bootstrap
- attach flows
- typed host catalog
- provider broker
- task graph
- review state
- proof bundles
- routing
- benchmarks
- ship metrics
- runtime exports
- plugin and skill generation

MCP is the access surface, not the whole system.

## Why CK is not “just a review tool”

Because review is only one stage.

CK also does:

- intent compilation
- posture compilation
- runtime recommendation
- task continuity
- validation before action
- governed execution/delegation
- proof capture
- ship readiness

## Why CK is not “just a wrapper around one host”

Because the product is intentionally designed to outlive any one host.

CK keeps:

- support typed and explicit
- host-specific surfaces honest
- governance portable
- proofs and findings outside one vendor UI
- runtime and provider control independent where needed

That is why it can attach to many hosts, export runtime bundles, and still provide fallback governance when native attach does not exist.

## How CK handles unsupported or partially supported tools

This is another important part of how it works exactly.

CK does **not** require universal native integration to be useful.

For unsupported tools, the honest path is:

1. bootstrap the governed project
2. let the external tool operate
3. use `controlkeel watch`, findings, proofs, and `ck_validate`
4. use proxy or provider-compatible endpoints when the tool supports them

This is why CK’s support story is more credible than systems that say “everything is supported” without explaining the mechanism.

## The main product surfaces

The product is expressed through several major surfaces.

### CLI

The CLI handles:

- bootstrap
- attach
- provider configuration
- status
- findings
- proofs
- review flows
- skill install/export
- runtime export
- task/session run
- host doctoring

### Web app

The web app handles:

- onboarding
- Mission Control
- findings browser
- proof browser
- ship dashboard
- skills/install/export visibility
- deployment advisor

### MCP and hosted protocols

These expose the agent-facing governed tool contract.

### Generated assets

CK also ships generated host-native assets such as:

## Step 11: autonomy and improvement loop summaries

CK does not treat every session as the same kind of "agent run." It now derives three additional views from the same governed session record:

- **autonomy profile**: whether the session is effectively advise-only, supervised execute, guarded autonomy, or long-running autonomy
- **outcome profile**: whether the work is aimed at task delivery or an explicit KPI / longer-horizon outcome
- **improvement loop**: whether CK has enough evidence from traces, failure clusters, governance coverage, proofs, and benchmark coverage to recommend the next loop-closing move

Those views are derived, not magical. They come from:

- session metadata and execution brief
- risk tier and approval-heavy constraints
- cyber access mode for security work
- current task / proof state
- trace packet and failure-cluster availability
- governance coverage signal (which governance tools are load-bearing vs unused across recent sessions)
- benchmark suite availability for the current domain

That means CK can say something operationally useful like:

- "this is supervised execute, not long-running autonomy"
- "this mission has an explicit KPI"
- "the next leverage point is turning failure clusters into evals"

without inventing a second workflow engine or pretending it has unrestricted autonomy.

- plugin bundles
- MCP config
- command bundles
- skills
- rules
- workflows
- hooks
- runtime exports

That is how the same control model becomes usable in many host environments without pretending they all behave the same way.

## The simplest exact summary

ControlKeel works by taking agent work through a governed control loop:

1. understand the work boundary
2. compile posture and runtime recommendation
3. bind the work to session/task state
4. expose governed context and tools to the agent
5. validate risky content before execution
6. persist findings and review state
7. capture proof and continuity artifacts
8. evaluate readiness, outcomes, and benchmarks

The reason it feels different from a host is that a host usually helps an agent **do work**.

ControlKeel helps a team **govern work done by agents**.

That difference is the entire product.
