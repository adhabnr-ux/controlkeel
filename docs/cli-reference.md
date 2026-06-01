# CLI Reference

This document covers all the command line topics available in ControlKeel.

```
ControlKeel help

What CK can do:
  - bootstrap a governed project with local MCP access
  - attach supported coding hosts such as Codex, Claude, Cursor, OpenCode, and more
  - surface findings, plan reviews, proofs, and release-readiness checks
  - run or hand off governed tasks through supported agent execution paths
  - export native bundles, plugins, and hosted MCP/A2A access surfaces

Good starting points:
  - `controlkeel help getting-started`
  - `controlkeel help attach`
  - `controlkeel help codex`
  - `controlkeel help why is my task blocked`
  - `controlkeel help run agents`
  - `controlkeel help providers`
  - `controlkeel help troubleshooting`

Common first commands:
  - `controlkeel init`
  - `controlkeel attach codex-cli`
  - `controlkeel attach doctor`
  - `controlkeel status`
  - `controlkeel findings`
  - `controlkeel agents doctor`

Topics:
  - overview
  - getting-started
  - attach
  - codex
  - review
  - findings
  - run
  - skills
  - providers
  - troubleshooting
  - mcp

```

## overview
```
ControlKeel help

Query: overview
Matched topic: What ControlKeel does

ControlKeel governs agent work with project bootstrapping, MCP access, findings, reviews, proofs, agent routing, and release-readiness checks.

Try these commands:
  - `controlkeel setup`
  - `controlkeel attach codex-cli`
  - `controlkeel status`
  - `controlkeel findings`
  - `controlkeel help getting-started`

Guidance:
  - Use `controlkeel setup` to bootstrap the governed project and see recommended attach and runtime-export paths.
  - Use `controlkeel attach <agent>` to wire an agent to CK.
  - Use `controlkeel status`, `findings`, and `proofs` to inspect governed state.

Related help:
  - `controlkeel help getting-started`
  - `controlkeel help attach`
  - `controlkeel help review`
```

## getting-started
```
ControlKeel help

Query: getting-started
Matched topic: Getting started

Use this when you are setting up CK for the first time or want the shortest path from install to governed agent work.

Try these commands:
  - `controlkeel setup`
  - `controlkeel attach codex-cli`
  - `controlkeel status`
  - `controlkeel help attach`

Guidance:
  - Run `controlkeel setup` inside the project you want to govern.
  - Attach a client such as `codex-cli`, `claude-code`, `cursor`, or `opencode`.
  - Check the result with `controlkeel status` and `controlkeel findings`.

Related help:
  - `controlkeel help attach`
  - `controlkeel help providers`
  - `controlkeel help mcp`
```

## attach
```
ControlKeel help

Query: attach
Matched topic: Attach and host setup

Attach registers CK with your coding host, writes host-specific companion files, and usually installs native bundles unless you pass `--mcp-only` or `--no-native`.

Try these commands:
  - `controlkeel attach codex-cli --scope project`
  - `controlkeel attach claude-code`
  - `controlkeel attach cursor`
  - `controlkeel attach doctor`
  - `controlkeel help codex`

Guidance:
  - Use `--scope project` when you want repo-local host files.
  - Use `--scope user` for hosts that support shared user config such as Codex or Claude.
  - Use `--mcp-only` when you only want MCP registration and not native companion files.
  - Run `controlkeel attach doctor` after attach to confirm host wiring and provider readiness.

Related help:
  - `controlkeel help codex`
  - `controlkeel help mcp`
  - `controlkeel help skills`
```

## codex
```
ControlKeel help

Query: codex
Matched topic: Codex CLI integration
Matched agent: Codex CLI

Codex is a review-only host in CK. CK writes `.codex/config.toml`, `.codex/hooks.json`, native `.codex/skills`, multiple Codex custom agents, review commands, and `.agents/skills` compatibility copies for the governed repo or user scope.

Try these commands:
  - `controlkeel attach codex-cli --scope project`
  - `controlkeel attach codex-cli --scope user`
  - `controlkeel attach codex-cli --mcp-only`
  - `controlkeel plugin install codex --scope project`

Agent-specific notes:
  - attach command: `controlkeel attach codex-cli`
  - phase model: review_only
  - review path: browser_review
  - scope: user, project
  - companion files: .agents/skills, .codex/skills, .codex/config.toml, .codex/hooks.json, .codex/hooks, .codex/agents/controlkeel-operator.toml, .codex/agents/controlkeel-reviewer.toml, .codex/agents/controlkeel-docs-researcher.toml, .codex/commands/controlkeel-review.md, .codex/commands/controlkeel-annotate.md, .codex/commands/controlkeel-last.md, .codex/commands/controlkeel-diff-review.md, .codex/commands/controlkeel-completion-review.md, .mcp.json, AGENTS.md
  - direct installs: Codex via npm: npm install -g @openai/codex | Codex via Homebrew: brew install --cask codex | CK attach: controlkeel attach codex-cli | Codex plugin: controlkeel plugin install codex

Guidance:
  - Project scope writes `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks`, `.codex/skills`, `.codex/agents`, `.codex/commands`, and `.agents/skills` into the repo.
  - User scope writes `~/.codex/config.toml`, `~/.codex/hooks.json`, `~/.codex/hooks`, `~/.codex/skills`, `~/.codex/agents`, `~/.codex/commands`, and `~/.agents/skills`.
  - Codex custom agents now include `controlkeel-operator`, `controlkeel-reviewer`, and `controlkeel-docs-researcher` for separate execution, review, and documentation workflows.
  - Codex only loads repo `.codex/` layers when the project is trusted, so trust the repo if hooks or config appear to be ignored.
  - Restart Codex after `controlkeel attach codex-cli` or `controlkeel plugin install codex` so new hooks, custom agents, and marketplace changes are reloaded.

Related help:
  - `controlkeel help attach`
  - `controlkeel help review`
  - `controlkeel help skills`
```

## review
```
ControlKeel help

Query: review
Matched topic: Review and approvals

CK uses plan reviews, diff reviews, findings, and feedback loops to keep agent work policy-gated instead of silently shipping.

Try these commands:
  - `controlkeel review diff --base main --head HEAD`
  - `controlkeel review plan submit --stdin`
  - `controlkeel review plan open --id 123`
  - `controlkeel review plan respond 123 --decision approved`

Guidance:
  - Use `review plan submit` when an agent needs human approval on a plan.
  - Use `review diff`, `review pr`, or `review socket` for explicit review passes.
  - If a task is blocked, check `controlkeel findings` and open review state first.

Related help:
  - `controlkeel help findings`
  - `controlkeel help run`
  - `controlkeel help codex`
```

## findings
```
ControlKeel help

Query: findings
Matched topic: Findings and blocked work

Findings are CK's policy and validation output. Open or blocked findings can stop task execution until they are reviewed or resolved.

Try these commands:
  - `controlkeel findings`
  - `controlkeel findings --severity high`
  - `controlkeel findings translate`
  - `controlkeel approve <finding-id>`

Guidance:
  - Start with `controlkeel findings` to see what is open or blocked.
  - Use `findings translate` if you want the output rewritten into plain English.
  - Approval only clears the governance gate when the workflow allows it; some findings still require real remediation.

Related help:
  - `controlkeel help review`
  - `controlkeel help run`
  - `controlkeel help policy`
```

## run
```
ControlKeel help

Query: run
Matched topic: Running agents from CK

CK can either run an agent directly, hand work off to an external host, or export a runtime package depending on the integration's execution model.

Try these commands:
  - `controlkeel agents doctor`
  - `controlkeel run task <id> --agent codex-cli --mode embedded`
  - `controlkeel run session <id>`
  - `controlkeel sandbox status`

Guidance:
  - Use `agents doctor` to see which agents are runnable and in what mode.
  - Use `run task` for a specific governed task or `run session` for all ready tasks.
  - If a run does not proceed, check findings and pending reviews because CK keeps execution policy-gated.

Related help:
  - `controlkeel help findings`
  - `controlkeel help review`
  - `controlkeel help attach`
```

## skills
```
ControlKeel help

Query: skills
Matched topic: Skills, bundles, and plugins

CK can export or install host-native bundles, open-standard skills, and plugin packages for supported agents.

Try these commands:
  - `controlkeel skills list`
  - `controlkeel skills export --target codex`
  - `controlkeel skills install --target codex --scope project`
  - `controlkeel plugin export codex`

Guidance:
  - Use `skills list` to inspect target compatibility and bundle health.
  - Use `skills export` when you want a dist bundle without installing it yet.
  - Use `plugin export` or `plugin install` for the hosts that ship plugin bundles.

Related help:
  - `controlkeel help attach`
  - `controlkeel help codex`
  - `controlkeel help mcp`
```

## providers
```
ControlKeel help

Query: providers
Matched topic: Providers and model access

CK can use an attached host's provider bridge, a CK-owned provider profile, a local compatible backend, or heuristic mode when no provider is configured.

Try these commands:
  - `controlkeel provider list`
  - `controlkeel provider doctor`
  - `controlkeel provider set-key openai --value "$OPENAI_API_KEY"`
  - `controlkeel provider set-base-url openai --value http://127.0.0.1:1234`

Guidance:
  - Use `provider doctor` if CK seems unable to run model-backed advisory flows.
  - Use `set-base-url` and `set-model` for OpenAI-compatible local or hosted backends.
  - Some hosts, such as Codex CLI and Claude Code, can bridge provider access for CK.

Related help:
  - `controlkeel help getting-started`
  - `controlkeel help run`
  - `controlkeel help codex`
```

## troubleshooting
```
ControlKeel help

Query: troubleshooting
Matched topic: MCP troubleshooting

Use this when CK tools return Not connected, a host says failed to connect, or attach looks successful but MCP calls fail.

Try these commands:
  - `controlkeel attach doctor`
  - `controlkeel status`
  - `controlkeel provider doctor`
  - `controlkeel attach claude-code`

Guidance:
  - Run `controlkeel attach doctor` first to confirm attached and runnable host state.
  - For Claude, run `claude mcp get controlkeel` and re-attach if status is failed.
  - If a host cannot launch `controlkeel`, set `CONTROLKEEL_BIN` to an absolute binary path and attach again.
  - After startup, wait 2-5 seconds and retry once to avoid transient MCP backend boot races.

Related help:
  - `controlkeel help attach`
  - `controlkeel help mcp`
  - `controlkeel help providers`
```

## mcp
```
ControlKeel help

Query: mcp
Matched topic: MCP, hosted access, and remote clients

CK exposes a local stdio MCP server for repo-local trust and also supports hosted MCP plus a minimal A2A surface for remote machines.

Try these commands:
  - `controlkeel mcp --project-root /abs/path`
  - `controlkeel service-account create --workspace-id 1 --name ci-mcp --scopes "a2a:access mcp:access budget:write context:read cost:read delegate:run finding:write memory:write memory:read outcome:read outcome:write regression:write review:respond review:read review:write route:read skills:read validate:run"`
  - `controlkeel registry status acp`
  - `controlkeel help attach`

Guidance:
  - Use local stdio MCP for native repo-local attachments.
  - Use service accounts plus `POST /oauth/token` and `POST /mcp` for hosted remote access.
  - Use the A2A surface only for the narrow governed capabilities CK advertises.

Related help:
  - `controlkeel help attach`
  - `controlkeel help providers`
  - `controlkeel help skills`
```

