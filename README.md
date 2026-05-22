# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)
[![Socket Badge](https://badge.socket.dev/npm/package/@aryaminus/controlkeel)](https://socket.dev/npm/package/@aryaminus/controlkeel/overview)
[![controlkeel MCP server](https://glama.ai/mcp/servers/aryaminus/controlkeel/badges/score.svg)](https://glama.ai/mcp/servers/aryaminus/controlkeel)

> Agent output is cheap. Governed delivery is not. Keep engineers at the helm.

**ControlKeel shapes itself around how you actually steer.** It makes your judgment legible, durable, and enforceable - and learns from every decision you make (approved, denied, escalated, dismissed) so it aligns to your real working pattern, not a spec doc you might not re-read. Under that surface, CK is the control plane for agent-led software delivery. It sits between your coding agents and production as a portable "company brain": comparing *intended* delivery against *actual* delivery and turning raw agent intent into audited tasks through findings and proofs. It catches the governance drift by enforcing validation and review gates, while keeping work resumable across any host.

---

## Why this exists

If you're using an AI agent today, you probably have an `*.md` telling it how to behave. But a rules/specs file is just a promise made *to* the model. **ControlKeel enforces the output.** It uses a deterministic scanner to check what the model actually produced, blocking or flagging violations before they ever touch your main branch. Beyond just catching bugs, CK solves the "Unknown Unknowns" problem that makes working with AI miserable: having to re-explain your domain knowledge in every single session.

- **Rules that actually work:** Deterministic enforcement, not just LLM suggestions.
- **Portability:** Move between OpenCode, Claude Code, Cursor, or any supported host without losing your task state with task continuity and resume context.
- **Persistence:** Typed memory with citations and "proof bundles" with policy packs mean your agent remembers *why* decisions were made, even weeks later as findings become living knowledge with workspace snapshots.
- **Governance:** Built-in review gates, approval flows, and budget controls that work the same way regardless of which host you use.
- **Observability:** Local loop that turns governance evidence into human-gated regression testing and evidence-driven improvement without sending telemetry to a hosted service.

ControlKeel transforms your domain knowledge from "shelfware" documentation into a living system that remembers, enforces, and evolves.

---

## Quick start

### One-line setup via your agent

Copy/paste this into your agent (OpenCode, Codex, Claude, or another supported host):

```text
Set up ControlKeel for this repository. Read and follow https://raw.githubusercontent.com/aryaminus/controlkeel/main/README.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/getting-started.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/direct-host-installs.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/support-matrix.md, and https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/agent-integrations.md. Detect this host, install CK if missing, run controlkeel setup, then attach the strongest useful host path with plugin and MCP plus skills/hooks/agents as available. Run controlkeel attach doctor, provider doctor, status, findings, controlkeel me, and the host-specific MCP check; apply only safe local fixes and re-verify. Redact proxy tokens and secrets from shared logs. Pause and ask before continuing if the host needs trust, manual provider config, a restart after attach/plugin changes, or a plan-review approval that cannot auto-wait. For Codex, ensure the project is trusted and restart Codex after attach/plugin changes.
```

### Install ControlKeel

```bash
# Homebrew (macOS and Linux x86_64)
brew tap aryaminus/controlkeel && brew install controlkeel

# npm bootstrap (macOS x86_64/arm64, Linux x86_64, Windows x86_64)
npm i -g @aryaminus/controlkeel
# or: pnpm add -g @aryaminus/controlkeel
# or: yarn global add @aryaminus/controlkeel

# one-off run
npx @aryaminus/controlkeel@latest

# release installers
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
```

```powershell
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

### First governed run

```bash
# 1. Start ControlKeel
controlkeel

# 2. In the target repo, bootstrap and inspect the environment
controlkeel setup

# 3. Attach a supported host. OpenCode is the recommended first path
controlkeel attach opencode   # or codex-cli, claude-code, copilot, etc.

# 4. Inspect governance state
controlkeel status
controlkeel findings

# 5. See your steering pattern
controlkeel me

# 6. Use guided CLI help whenever you need it
controlkeel help
controlkeel help opencode
controlkeel help "how do i attach codex"
```

For a full first-run walkthrough, see [docs/getting-started.md](docs/getting-started.md). For large codebase deployment patterns, see [docs/large-codebase-patterns.md](docs/large-codebase-patterns.md).

---

## Why use ControlKeel? Benchmark-backed comparison

ControlKeel adds a governance layer around agent output: fast deterministic checks, optional in-agent CK validation, review gates, proof, and budget visibility. The table below is intentionally user-facing: it shows what a team gets from each level of CK integration without requiring you to run the benchmark yourself. Full reproducibility details and caveats live in [docs/benchmark-evidence.md](docs/benchmark-evidence.md).

### OpenCode / GPT-5.5 comparison (`host_comparison_v1`, 12 risky scenarios)

| Option | What it means | Catch | Block | Median time | Tokens | Best use |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Raw OpenCode | Ask the model and trust the answer | 1/12 | 0/12 | 17,050 ms | 290,327 | Baseline only; not enough for risky changes |
| CK-attached | CK is installed/available, model may call it | 4/12 | 3/12 | **10,818 ms** | 254,581 | Lightweight default when you want CK available without forcing tool use |
| Exhaustive CK-active | Ask the model to inspect every CK surface | 2/12 | 0/12 | 47,560 ms | 510,280 | Demonstrates surface availability, but too slow/expensive for routine use |
| **CK-bounded active** | Model calls CK context + validation, then stops | **5/12** | **3/12** | 23,772 ms | **255,941** | Best practical active-governance tradeoff so far |
| **CK deterministic scanner** | CK validates directly, no model required | **12/12** | **9/12** | **~50 ms** | **0 provider tokens** | Fastest enforcement baseline; ideal for preflight and CI-style checks |

What users should take away:

- **Security lift:** CK raises systematic detection from raw model output's 1/12 to 5/12 with bounded active governance, and 12/12 with direct deterministic validation.
- **Efficiency:** bounded active used about half the tokens of exhaustive active while catching more issues.
- **Cost control:** OpenCode reported `$0` cost in JSON events, so we treat tokens/time as the reliable cost proxy. Direct CK scanning uses no provider tokens.
- **Practical workflow:** use deterministic CK validation as the fast gate, and use bounded active governance when you want the agent itself to consult CK before responding.

### Other agents (pending)

| Host | Mode | Suite | Catch | Block |
| --- | --- | --- | ---: | ---: |
| Codex | Raw / no CK | `host_comparison_v1` | TBD | TBD |
| Codex | CK-attached | `host_comparison_v1` | TBD | TBD |
| Claude Code | Raw / no CK | `host_comparison_v1` | TBD | TBD |
| Claude Code | CK-attached | `host_comparison_v1` | TBD | TBD |

To run a host comparison: `controlkeel benchmark run --suite host_comparison_v1 --subjects controlkeel_validate,<host>_manual`. See [docs/benchmark-guide.md](docs/benchmark-guide.md).

---

## Published surfaces

ControlKeel has one primary CLI bootstrap package, published companion packages for specific hosts, and generated distribution bundles for all supported integrations.

### Core Bootstrap Package

| Surface | Version | Install / use |
| --- | --- | --- |
| ControlKeel CLI bootstrap | [![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel) | `npm i -g @aryaminus/controlkeel` |

**This is the required foundation** - install this first before using any other ControlKeel packages or features.

### Companion Packages

Published npm packages for direct host integration:

| Package | Host | Version | Install |
| --- | --- | --- | --- |
| OpenCode companion | OpenCode | [![npm opencode](https://img.shields.io/npm/v/%40aryaminus/controlkeel-opencode.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-opencode) | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` |
| Pi extension | Pi | [![npm pi](https://img.shields.io/npm/v/%40aryaminus/controlkeel-pi-extension.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel-pi-extension) | `pi install npm:@aryaminus/controlkeel-pi-extension` |

**Note:** After installing companion packages, also run `controlkeel attach <host>` for the full repo-local experience with commands, agents, and MCP config.

### Distribution Bundles

Generated bundles for 40+ hosts and runtimes, available via `controlkeel attach <host>` or `controlkeel runtime export <target>`:

| Bundle Type | Examples | How to Install |
| --- | --- | --- |
| Host native bundles | OpenCode, Claude Code, Codex, Copilot, Cursor, Windsurf, etc. | `controlkeel attach <host>` |
| Runtime bundles | Devin, Open SWE, Executor, Virtual Bash, Cloudflare Workers | `controlkeel runtime export <runtime>` |
| Framework adapters | Forge ACP, framework adapters | Generated via export system |
| Utility bundles | VS Code companion, GitHub repo, instructions-only | Included in releases |

**See [docs/packages.md](docs/packages.md) for the complete package catalog and detailed installation instructions.**

### Skills.sh / AgentSkills

ControlKeel skills are also available through the public [skills.sh](https://skills.sh/) registry:

| Surface | Install |
| --- | --- |
| Whole CK skill collection | `npx skills add https://github.com/aryaminus/controlkeel` |
| Single CK governance skill | `npx skills add https://github.com/aryaminus/controlkeel --skill controlkeel-governance` |

### Release Bundles

Tagged GitHub releases include:

- Platform binaries (macOS, Linux, Windows)
- Plugin tarballs for various hosts
- Exported native bundles
- `controlkeel-vscode-companion.vsix`

[![GitHub release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg?label=release%20bundles)](https://github.com/aryaminus/controlkeel/releases/latest)

---

## How OpenCode is configured with ControlKeel

OpenCode is the primary host used in the benchmark evidence above, and CK supports it through two complementary paths:

1. `controlkeel attach opencode` writes repo-local `.opencode/` assets, MCP configuration, commands, agents, skills, and `.agents/skills` compatibility copies.
2. The published `@aryaminus/controlkeel-opencode` companion can be added to `opencode.json` for the direct plugin-package path.
3. OpenCode can call `ck_context` / `ck_context_pack` to reacquire bounded session state, current task, proof summary, memory hits, resume packet, budget summary, review gate state, and workspace context without relying on chat history.
4. OpenCode can call `ck_validate`, `ck_review_submit`, `ck_memory_record`, and `ck_budget` so validation, approvals, durable memory, and spend evidence stay in CK rather than in one host runtime.

The same governed loop is available to OpenCode, Codex, Claude Code, Copilot, and other supported hosts, but the README guidance leads with OpenCode because that is the best current host-backed evidence path in this repository.

---

## What ControlKeel provides beyond validation

Validation is the most visible part. CK also provides:

**Governed context for agents (`ck_context`)** — bounded, session-aware, workspace-aware state: current task, proof summary, memory hits, resume packet, workspace snapshot, budget summary, recent transcript events. Agents start from grounded context instead of raw chat history or repeated shell exploration.

**Task continuity and resume** — sessions, tasks, task graph, checkpoints, and resume packets. Work survives runtime restarts and host switches.

**Findings and review gates** — every blocked or warned pattern becomes a governed finding with state (open, blocked, escalated, approved, denied), human gate hints, and Mission Control visibility. Review is part of the delivery system, not detached commentary.

**Proof bundles and typed memory** — immutable proof bundles capture what happened, what was reviewed, what was validated, and what findings existed. CK also records important briefs, reviews, checkpoints, findings, proof events, and decisions as typed memory so agents can retrieve citable continuity later.

**Budget and cost control** — session budgets, 24-hour rolling limits, proxy token estimates, circuit breakers on API-call rate, file-modification rate, and budget-burn rate. See [docs/cost-governance.md](docs/cost-governance.md).

**Cross-host consistency** — the same governance loop works across OpenCode, Codex, Claude Code, Copilot, Cline, Windsurf, Continue, Goose, Roo Code, and others. Project binding plus `ck_context`/typed memory/resume packets let a later host reacquire the same governed state. See [docs/support-matrix.md](docs/support-matrix.md).

**Ship readiness** — deploy-ready proof state, outcome metrics, and comparative benchmark evidence. The question is not just "did the agent finish?" but "is this ready to ship?"

**Local observability and learning loop** — a local-first cockpit (web, CLI, and MCP) that reconstructs session runs, timelines, memory quality, cost trends, and benchmark history from governance evidence. Operators can save eval candidates, draft and approve benchmark suites, detect regressions, and review promotion candidates — all human-gated, all local, no telemetry sent to a hosted service. Use `controlkeel obs loop` for a canonical learning-loop status report. See [docs/observability-feedback-loop.md](docs/observability-feedback-loop.md).

**Governance for company context graphs** — as the industry moves from retrieval-based agents to synthesized "company brains," ControlKeel provides the governance layer that makes context graphs trustworthy, auditable, and portable. CK validates synthesized context, tracks proof bundles for auditability, ensures cross-host portability, and provides typed memory that captures accumulated understanding. See [docs/explaining-controlkeel.md](docs/explaining-controlkeel.md) for details.

**Adaptive tool groups** — automatic tool selection optimization that learns usage patterns over time and provides 40-60% token reduction without manual configuration. Smart defaults based on project type detection, per-project preference persistence, and seamless integration across all CK paths (MCP, CLI, skills, web, hooks, plugins). See [docs/ADAPTIVE_TOOL_GROUPS.md](docs/ADAPTIVE_TOOL_GROUPS.md) for details.

---

## Local observability feedback loop

ControlKeel can turn local governance evidence into a human-gated regression loop without sending telemetry to a hosted service or automatically changing policy, router, prompt, or autofix artifacts. A typical local loop is:

```bash
controlkeel obs evals save
controlkeel obs benchmarks draft
controlkeel obs benchmarks drafts
controlkeel obs benchmarks approve <draft-id>
controlkeel obs benchmarks materialize
controlkeel obs benchmarks run --dry-run --subjects controlkeel_validate
controlkeel obs benchmarks run --execute --suite <observability-suite> --subjects controlkeel_validate
controlkeel obs benchmarks history
controlkeel obs promotions
```

Safety boundaries are explicit: draft approval only changes local draft review state; materialization only creates local `Benchmark.Suite` and `Benchmark.Scenario` rows; benchmark execution is CLI-only and requires explicit operator intent; promotion candidates are advisory reports with no automatic mutation. Use `controlkeel obs import <file> --dry-run|--persist` for local observability snapshots and `controlkeel obs regressions` for the broader benchmark posture. See [docs/observability-feedback-loop.md](docs/observability-feedback-loop.md).

---

## Supported hosts

ControlKeel supports hosts through a few real mechanisms:

- **Native attach**: `controlkeel attach <host>` installs MCP config plus the strongest repo-native companion CK can truthfully ship.
- **Direct host install**: some hosts also support a package, plugin, VSIX, or extension-link path.
- **Hosted protocol access**: remote clients can use hosted MCP and minimal A2A.
- **Runtime export**: headless systems such as Devin and Open SWE get runtime bundles instead of unsupported native attach commands.
- **Provider-only and fallback governance**: unsupported generators can still be governed through bootstrap, findings, proofs, and validation flows.

Common attach targets today:

- Plugin-native and benchmarked first path: `opencode`
- Hook-native: `claude-code`, `copilot`, `windsurf`, `cline`, `kiro`, `augment`
- Other plugin-native: `amp`
- File-plan-mode: `pi`
- Prompt or command-native: `continue`, `gemini-cli`, `goose`, `roo-code`
- Hook, skill, and MCP-native with headless/remote support: `letta-code`
- Browser or embed companion: `vscode`
- Review-only, command-driven, or local-plugin-capable: `codex-cli`, `aider`

Use the docs below for the precise truth per host:

- [docs/direct-host-installs.md](docs/direct-host-installs.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)

---

## What ControlKeel exposes

Web app:

- `/start` for onboarding and execution brief creation
- `/missions/:id` for mission control and approvals
- `/findings` for cross-session findings
- `/proofs` for immutable proof bundles
- `/skills` for install/export compatibility and bundle inventory
- `/ship` for deploy readiness and session metrics
- `/benchmarks` for benchmark runs and cross-agent comparison
- `/observability` for local workspace overview and session timeline
- `/observability/loop` for the read-only human-gated learning loop

CLI:

```bash
controlkeel attach <agent>
controlkeel status
controlkeel findings
controlkeel proofs
controlkeel update
controlkeel skills list
controlkeel tool groups suggest
controlkeel plugin install codex
controlkeel run task <id>
controlkeel benchmark run --suite vibe_failures_v1 --subjects controlkeel_validate
controlkeel obs loop
controlkeel obs status
controlkeel help
```

For OpenCode, use `controlkeel attach opencode` for repo-local MCP/commands/skills/agents, and add the published `@aryaminus/controlkeel-opencode` package in `opencode.json` when you want the direct plugin package as well.

For Codex there are two different CK install paths:

- `controlkeel attach codex-cli` installs the native `.codex/` companion files, skills, commands, agents, and local MCP wiring.
- `controlkeel plugin install codex` installs a local plugin bundle plus a local marketplace manifest for repo-local or home-local discovery.

That local marketplace path is not the same thing as being listed in OpenAI's curated Codex plugin catalog.

Full command coverage is available in the CLI itself through `controlkeel help`.

For MCP tool details, hosted protocol access, and the exact `ck_context` contract, use [docs/agent-integrations.md](docs/agent-integrations.md) and [docs/support-matrix.md](docs/support-matrix.md).

---

## Docs

Start here:

- [docs/README.md](docs/README.md)
- [docs/getting-started.md](docs/getting-started.md)
- [docs/direct-host-installs.md](docs/direct-host-installs.md)
- [docs/explaining-controlkeel.md](docs/explaining-controlkeel.md)

Reference:

- [docs/large-codebase-patterns.md](docs/large-codebase-patterns.md)
- [docs/qa-validation-guide.md](docs/qa-validation-guide.md)
- [docs/support-matrix.md](docs/support-matrix.md)
- [docs/agent-integrations.md](docs/agent-integrations.md)
- [docs/ADAPTIVE_TOOL_GROUPS.md](docs/ADAPTIVE_TOOL_GROUPS.md)
- [docs/autonomy-and-findings.md](docs/autonomy-and-findings.md)
- [docs/benchmarks.md](docs/benchmarks.md)
- [docs/benchmark-guide.md](docs/benchmark-guide.md)
- [docs/benchmark-evidence.md](docs/benchmark-evidence.md)
- [docs/cost-governance.md](docs/cost-governance.md)

Architecture and release operations:

- [docs/control-plane-architecture.md](docs/control-plane-architecture.md)
- [docs/host-surface-parity.md](docs/host-surface-parity.md)
- [docs/how-controlkeel-works.md](docs/how-controlkeel-works.md)
- [docs/integration-validation-checklist.md](docs/integration-validation-checklist.md)
- [docs/release-verification.md](docs/release-verification.md)

---

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds ship through Burrito and GitHub Releases.

To run the benchmark suite locally:

```bash
controlkeel benchmark run --suite vibe_failures_v1 --subjects controlkeel_validate
controlkeel obs loop
controlkeel obs status
controlkeel benchmark run --suite benign_baseline_v1 --subjects controlkeel_validate
controlkeel benchmark export <RUN_ID> --format json
```

See [docs/benchmark-guide.md](docs/benchmark-guide.md) for multi-host comparison setup and how to add Codex or OpenCode as subjects.

Local observability web cockpit includes `/observability` for workspace overview and `/observability/loop` for the read-only human-gated learning loop.
