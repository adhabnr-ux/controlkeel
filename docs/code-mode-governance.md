# Code-mode and generated-script governance

Large API surfaces should not become hundreds or thousands of always-loaded MCP tools. ControlKeel prefers progressive discovery first, then typed/code-mode execution when an agent needs to orchestrate many API endpoints without filling the transcript with unused tool schemas.

## Product stance

### Why code-mode exists

Large API surfaces do not translate cleanly into "one tool per endpoint" without blowing up context. Even if the protocol supports it, dumping thousands of tools into an agent's context produces tool-definition bloat: most tokens are spent on schemas that are never invoked.

Matt from Cloudflare encountered this directly when trying to expose their entire API (2,600 endpoints, OpenAPI spec 2.3M tokens) to agents. Converting to naive tools would result in 1.1M tokens - completely annihilating the context window even with the largest foundational models. This is not an MCP problem; it's a fundamental scalability issue with the "one tool per endpoint" pattern.

A practical alternative is to expose **typed SDKs or type signatures** as the compact representation of inputs and outputs, then let the agent generate a small amount of code against those types for the specific task. That code becomes the executable plan.

### TypeScript SDK pattern

Cloudflare's code mode approach demonstrates this pattern effectively: generate TypeScript types from OpenAPI specs, then let the model write code against those types. TypeScript provides a concise way to represent inputs and outputs that agents can reason about efficiently.

Instead of thousands of tool definitions, the agent receives:
- A typed SDK (generated from OpenAPI spec as the source of truth)
- The ability to write code against those types
- Execution in an isolated sandbox

This approach scales to entire APIs (Cloudflare exposes all 2,600+ endpoints this way) while keeping token usage minimal. As models improve, the generated code improves automatically - you benefit from better models without updating tool definitions.

CK's stance remains the same: code-mode is powerful because it is compact and expressive, but it must stay inside a default-deny execution boundary.

### Empirical evidence: monday.com case study

monday.com's Vibe coding agent, which generates entire applications against monday's GraphQL API, provides concrete empirical data comparing SDK vs MCP approaches. The test used the same model, same four tasks, and same staging board with identical correct outcomes.

**Cost comparison (per task):**
- SDK setup: 15,626 input tokens (mean), 1.0 model steps, ~9.5s wall-clock, $0.025/task
- MCP setup: ~158,000 input tokens (mean), 4.0 model steps, ~26s wall-clock, $0.210/task
- **Result: 8.4× the inference cost per task for the same answer**

**Where the MCP tokens went:**
monday's official MCP server ships ~34k tokens of tool definitions on every model step. With the agent averaging 4 steps per task (discover schema → write code → validate → sometimes retry), you accumulate 150–200k input tokens before the agent even submits a solution. The SDK prompt is also heavy (~12k tokens) but the agent reads it once, and it's stable across tasks — easily cached.

**Why monday's GraphQL makes the gap especially wide:**

1. **Per-board schemas**: Every customer's board has user-defined columns with opaque IDs like `color_mm3b9bgw` and `numeric_jjk44p2x`. The SDK lets agents write `board.items().withColumns(["status", "budget"])` and resolves names to IDs internally. With MCP, agents must call `get_board_info`, scan column lists, and thread opaque IDs through every query.

2. **Column-value JSON shapes**: monday's column values are JSON-encoded with varying shapes per column type (Status: `{label: "Done"}`, People: `{personsAndTeams: [{id: 4828557, kind: "person"}]}`, Date: `{date: "YYYY-MM-DD"}`). The SDK handles encoding/decoding; with MCP, agents build each shape by hand from schema docs — a place to silently get it wrong.

3. **Status filters**: Status filters require an index, not the label. SDK: `board.items().where({Status: "Done"})` works. MCP: call `get_board_info`, fetch `settings_str`, parse JSON, build label-to-index map, look up index, pass `compare_value: ["2"]`. Six lines of plumbing on every filter.

**Code quality comparison:**

For a bulk multi-update task (set "Stuck" items to "In Progress" with effort 1):

- **SDK version**: 24 lines, 680 chars — clean, domain-readable code
- **MCP version**: 80 lines, 2,502 chars — verbose, filled with opaque IDs and JSON plumbing

The SDK code is short because the SDK encodes the answers once. MCP rediscovers them every time.

**Benefits beyond inference cost:**

1. **Future-proof generated apps**: When monday's GraphQL evolves (deprecations, response-shape changes, new pagination), SDK-generated code stays correct because the SDK adapts internally. MCP-generated apps are frozen against the API shape they were written against.

2. **Edge-case hardening**: The production Board SDK has years of accumulated handling for edge cases that look like one-liners but aren't (status writes that accept `{label}` or `{index}`, people IDs that must be integers, dropdown filters using `{ids}` vs `{labels}`). SDK-generated code inherits all of this.

3. **Context window efficiency**: At ~34k tokens of tool defs on every step, MCP permanently runs with ~17% less effective context window than SDK. This shows up as "more steps to converge" — the same tax.

**When MCP is the right tool:**

The blog post clarifies that MCP wins decisively when:
- The agent acts at agent-time, not generates code (Claude Desktop summarizing docs, analyst chat agent triaging tickets)
- The API surface is small (a dozen tools, not 66)
- The schema isn't user-defined per customer
- There's no downstream code-generation use case

The architectural question isn't "MCP or SDK." It's "what's the right primary surface for this agent's job?" For a coding agent generating per-customer apps against a complex API, the answer is the SDK. For an interactive agent calling the same API on behalf of one user at a time, the answer is MCP.

### Untrusted code execution risks

Running code generated by LLMs without validation was historically considered a critical vulnerability. Matt notes that a few years ago, proposing to "let a language model write code that we're going to execute for our users without looking at it, without reading it, without seeing what it does, that might have secrets access" would have been immediately rejected as a security risk.

Specific risks include:
- **File system access**: Reading or writing files that shouldn't be touched
- **Secrets exfiltration**: Reading secrets and sending them via network requests
- **Infinite loops**: Consuming all resources with never-ending computation
- **Resource consumption**: Running crypto miners or other resource-intensive operations
- **Network abuse**: Making unauthorized external requests

This is why CK's `CodeModePolicy` enforces default-deny for filesystem, network, secrets, shell, and deploy capabilities - and requires explicit approval before granting any of these.

### Programmable guardrails

Modern sandboxes like Cloudflare Workers (WorkerD), Deno, and Pydantic Monty provide programmable guardrails that can enable or disable capabilities at runtime. Cloudflare's WorkerD, for example, is a V8 isolate that can:

- **Disable process.env entirely** (with node compat off)
- **Block network access** via global functions
- **Enable selective network access** (only to specific domains)
- **Control resource limits** (runtime, memory, CPU)

These guardrails are often as simple as flipping a boolean in the server configuration, but can also use more sophisticated functions to enforce domain whitelists or other policies.

CK's `CodeModePolicy` supports this pattern through:
- `allowed_capabilities` list that can be dynamically scoped
- `network_allowlist` for selective network access
- Runtime and output limits to prevent resource exhaustion
- Rate policy with `respect_retry_after` to handle API rate limits

The key insight: the sandbox should be programmable, not just a fixed environment. This allows the same infrastructure to support different security postures for different use cases.

Code-mode is a compact plan format, not an automatic permission grant. Generated code, mini-scripts, and programmatic tool-calling snippets are treated as untrusted artifacts until CK validation and review approve the capabilities they need.

CK's current contract is advisory and policy-oriented:

- discover capabilities progressively instead of dumping full API surfaces into context
- describe large API interactions through typed SDKs or schemas when available
- run generated code only in an isolated runtime or host sandbox
- deny filesystem, shell, secrets, deploy, and network by default
- grant network only through reviewed allowlists and rate policy
- capture generated source, capability grants, runtime logs, egress summary, and result digests as proof artifacts

## CodeModePolicy

`ControlKeel.Runtime.CodeModePolicy` provides the code-backed policy map used by execution posture and future runtime exports. It currently records:

- `sandbox_required`
- `approval_required`
- `default_denied_capabilities`
- `allowed_capabilities`
- `network_allowlist`
- runtime and output limits
- rate policy with `respect_retry_after`
- proof artifacts expected from the runtime

`CodeModePolicy` does **not** execute code. It is consumed by `ck_execute_code`, which is intentionally narrow and refuses local host execution.

## `ck_execute_code`

`ck_execute_code` is the guarded MCP execution surface for generated code. It supports `dry_run` for planning and executes only through the Docker sandbox adapter when Docker is explicitly available. Local host execution is blocked because CK cannot make local `node`, `python`, or shell evaluation honor the default-deny filesystem/network/secrets contract.

Current execution constraints:

- supported languages: `javascript` and `python`
- supported execution sandbox: `docker` only
- network requests and network allowlists are still blocked until an enforcing egress proxy/runtime exists
- filesystem, secrets, shell, and deploy capabilities are always denied
- source is passed through `ck_validate` before execution
- runtime and output size are bounded
- output is truncated before returning to the agent

This gives users an executable path when they have a real sandbox configured, while keeping default installs safe through npm, Homebrew, GitHub Releases, and shell installers.

## Operating checklist

Before accepting generated code-mode output:

1. Confirm the brief actually needs code-mode or a large typed API surface.
2. Use progressive discovery (`ck_skill_list`, `ck_skill_load`, resources, typed API docs) before loading detailed schemas.
3. Run `ck_validate` on generated source and requested capabilities.
4. Require explicit approval for network, write APIs, deploy, shell, secrets, high-risk, or regulated data.
5. Keep concurrency and runtime bounded.
6. Respect `retry-after` and provider/API rate-limit telemetry.
7. Persist proof artifacts so saved mini-scripts can be revalidated before reuse.

## Secret and tool lockdown

Running agents on user machines or in shared environments demands fine-grained control over tool usage. Danilo's experience with the PostHog Wizard illustrates this: early versions would read .env files (necessary for writes), which meant sending user's ENV contents to cloud logs - "not ideal to be sending people's ENV contents up to a cloud and just like, all right, cool. That's sitting in someone's damn log that you don't know about."

The solution was fine-grain tool lockdown:
- **Restrict sensitive reads**: Lock down what the agent is allowed to do around ENV files
- **Provide safe alternatives**: Build tools that can do only what's needed (check presence of a key, write a new value) without reading sensitive data
- **No inference on sensitive data**: Ensure nothing goes up in terms of inference for sensitive files

CK's capability controls in `CodeModePolicy` already implement this pattern through:
- Default-deny for filesystem, secrets, and deploy capabilities
- Explicit allowlists for network access
- Scoped capability grants that must be validated before execution

The principle is: when you design these systems, you have fine grain control over tool usage. Decide which tools are okay, which kinds of reads are okay, and which kinds of reads are not okay.

## Saved mini scripts

A natural consequence of programmatic tool calling is that agents will generate useful code that users want to save and reuse. Matt describes this pattern:

- Users might save generated scripts for later reuse
- Scripts can be used for cron jobs (e.g., web scraping without knowledge of how web scraping works)
- When scripts break (web scraping is brittle), agents can auto-fix and resave them
- This creates a faster feedback loop than regenerating code from scratch each time

CK treats saved mini-scripts as governed artifacts, not as trusted automation. The operating checklist already includes revalidation after:
- Model/provider changes
- Tool schema changes
- Capability-surface changes
- Time passes and external APIs drift

This governance is critical because saved scripts have real-world impact (cron jobs, automated workflows) and must be revalidated as the environment changes.

## Server-side implications

When exposing APIs to agents via code mode, server-side infrastructure must be prepared for new patterns:

- **Rate limiting**: Agents can hammer APIs in loops across multiple sandboxes. APIs need robust rate limiting to protect against this.
- **Idempotency**: Agent-generated code may retry operations. APIs should be idempotent where possible.
- **Observability**: Understanding how agents use your API becomes important for optimization and abuse detection.

CK's rate policy in `CodeModePolicy` (with `respect_retry_after`) helps agents respect upstream rate limits, but the API itself must also have appropriate protections.
