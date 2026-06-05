# ControlKeel

[![CI](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/ci.yml)
[![Release Smoke](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml/badge.svg)](https://github.com/aryaminus/controlkeel/actions/workflows/release-smoke.yml)
[![Latest Release](https://img.shields.io/github/v/release/aryaminus/controlkeel.svg)](https://github.com/aryaminus/controlkeel/releases/latest)
[![npm bootstrap](https://img.shields.io/npm/v/%40aryaminus/controlkeel.svg)](https://www.npmjs.com/package/@aryaminus/controlkeel)
[![Socket Badge](https://badge.socket.dev/npm/package/@aryaminus/controlkeel)](https://socket.dev/npm/package/@aryaminus/controlkeel/overview)
[![controlkeel MCP server](https://glama.ai/mcp/servers/aryaminus/controlkeel/badges/score.svg)](https://glama.ai/mcp/servers/aryaminus/controlkeel)

> Turn the way your team works into enforceable memory for AI agents.

**ControlKeel is an agent control plane for governed AI engineering.** It turns your project rules, review taste and delivery habits into typed memory, policy checks and proof bundles through observation, findings and evaluation. It sits between your coding agents and production as a portable "company brain": comparing *intended* delivery against *actual* delivery and turning raw agent intent into audited tasks.

If you're using an AI agent today, you probably have an `*.md` telling it how to behave. But a rules/specs file is just a promise made *to* the model. **ControlKeel enforces the output.** Beyond just catching bugs, CK solves the "Unknown Unknowns" problem: having to re-explain your domain knowledge in every single session.

## Product loop

1. **Capture intent and policy** — scope, risk, budget, domain pack, and human taste become CK state.
2. **Validate agent output** — deterministic checks and optional advisory review produce findings before risky work reaches main.
3. **Gate only when needed** — humans approve high-impact actions when intent, risk, or policy requires it.
4. **Persist evidence** — findings, reviews, proofs, memory, cost, and task outcomes survive host switches.
5. **Improve with evals** — traces and recurring failures become bounded regression evidence for specific suites and subjects.

ControlKeel transforms your domain knowledge from "raw" intent and "shelfware" documentation into a living system that remembers, enforces, and evolves.

## Quick start

### One-line setup via your agent

Copy/paste this into your agent (OpenCode, Codex, Claude, or another supported host):

```text
Set up ControlKeel for this repository. Read and follow https://raw.githubusercontent.com/aryaminus/controlkeel/main/README.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/getting-started.md, https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/support-matrix.md, and https://raw.githubusercontent.com/aryaminus/controlkeel/main/docs/agent-integrations.md. Install ControlKeel if missing, run `controlkeel setup`, detect this agent host, attach the strongest supported path with `controlkeel attach <host>`, then run `controlkeel attach doctor`, `controlkeel provider doctor`, `controlkeel status`, `controlkeel findings`, and the host-native MCP check. If CK is available only as MCP, call `ck_attach` for this host. Apply only safe local fixes and redact secrets from logs. Pause and ask before continuing if the host needs workspace trust, manual provider configuration, a restart after attach/plugin changes, or a plan-review approval that cannot auto-wait. Ensure the project is trusted and restart the host after attach/plugin changes.
```

### CLI install

Install the CLI:

```bash
brew tap aryaminus/controlkeel && brew install controlkeel
# or
npm i -g @aryaminus/controlkeel
# or
curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex
```

First governed run:

```bash
controlkeel
controlkeel setup
controlkeel attach opencode   # or another supported host
controlkeel attach doctor
controlkeel provider doctor
controlkeel status
controlkeel findings
```

For the complete first-run path, use [docs/getting-started.md](docs/getting-started.md). For host truth, use [docs/support-matrix.md](docs/support-matrix.md) and [docs/agent-integrations.md](docs/agent-integrations.md).

## Benchmark-backed evidence

ControlKeel includes a persisted benchmark engine. Current user-facing evidence is bounded to the named suite, subject, and scoring definition below; full caveats live in [docs/benchmarks.md](docs/benchmarks.md).

### OpenCode / GPT-5.5 comparison (`host_comparison_v1`, 12 risky scenarios)

| Option | What it means | Catch | Block | Median time | Tokens | Best use |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Raw OpenCode | Ask the model and trust the answer | 1/12 | 0/12 | 17,050 ms | 290,327 | Baseline only; not enough for risky changes |
| CK-attached | CK is installed/available, model may call it | 4/12 | 3/12 | **10,818 ms** | 254,581 | Lightweight default when you want CK available without forcing tool use |
| Exhaustive CK-active | Ask the model to inspect every CK surface | 2/12 | 0/12 | 47,560 ms | 510,280 | Demonstrates surface availability, but too slow/expensive for routine use |
| **CK-bounded active** | Model calls CK context + validation, then stops | **5/12** | **3/12** | 23,772 ms | **255,941** | Best practical active-governance tradeoff so far |
| **CK deterministic scanner** | CK validates directly, no model required | **12/12** | **9/12** | **~50 ms** | **0 provider tokens** | Fastest enforcement baseline; ideal for preflight and CI-style checks |

Read the numbers precisely: *Catch* means CK produced the correct block/warn decision; *Block* means CK actively blocked. The stricter expected-rule-hit metric and reproduction notes are in [docs/benchmarks.md](docs/benchmarks.md).

## What ships today

- **Local governance:** CLI, stdio MCP, project binding, host attach/export bundles, scanner validation, findings, reviews, proof bundles, budgets, and typed memory.
- **Host and runtime support:** native attach for supported hosts, runtime exports for headless/outer-loop systems, hosted MCP/minimal A2A, and fallback validation/proxy paths.
- **Team/project operations:** org membership, invitations, OIDC/SAML auth surfaces, workspace GitHub repo bindings, service accounts, webhooks, workspace tool policy, and policy-set APIs.
- **Cloud evidence paths:** opt-in cloud telemetry, workspace keys, cloud run packages, runtime callbacks, and dormant-until-configured bidirectional sync for findings, reviews, digests, and memory records.
- **Observability loop:** timelines, memory quality, costs, trends, problem clusters, eval candidates, benchmark drafts/history, and promotion advisories.

## Docs map

- [docs/README.md](docs/README.md) — documentation map by job
- [docs/getting-started.md](docs/getting-started.md) — install to first finding
- [docs/support-matrix.md](docs/support-matrix.md) — canonical host/protocol inventory
- [docs/agent-integrations.md](docs/agent-integrations.md) — integration mechanisms and support tiers
- [docs/benchmarks.md](docs/benchmarks.md) — benchmark scoring, metadata, and claim discipline
- [docs/observability-feedback-loop.md](docs/observability-feedback-loop.md) — local evidence-to-regression loop
- [docs/api-reference.md](docs/api-reference.md) and [docs/cli-reference.md](docs/cli-reference.md) — code-aligned surfaces
- [docs/packages.md](docs/packages.md) — package and distribution catalog
- [docs/self-hosting.md](docs/self-hosting.md) — self-host deployment guidance

## Development

```bash
mix setup
mix phx.server
mix test
mix precommit
```

Phoenix + Ecto on SQLite. Uses `Req` for HTTP. Single-binary builds ship through Burrito and GitHub Releases.
