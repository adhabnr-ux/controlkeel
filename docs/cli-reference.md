# CLI Reference

The authoritative CLI reference is the live help system built into the `controlkeel` binary. This page points you to the right commands instead of duplicating help text that drifts.

## Getting started

```bash
controlkeel              # interactive help
controlkeel help         # full topic list
controlkeel help <topic> # detailed help for a topic
```

## Topics

Run `controlkeel help <topic>` for any of these:

- `overview` — what CK does and how it fits
- `getting-started` — install to first finding
- `attach` — attaching agent hosts
- `codex` — Codex CLI specifics
- `review` — plan review and approval gates
- `findings` — finding lifecycle and disposition
- `run` — running governed tasks and agents
- `sessions` — session management
- `skills` — AgentSkills discovery and activation
- `providers` — provider configuration
- `troubleshooting` — common issues
- `worktrees` — git worktree integration
- `checkpoints` — checkpoint and rollback
- `git` — git governance
- `monitoring` — observability and monitoring
- `mcp` — MCP server configuration

## Common commands

```bash
controlkeel init                  # bootstrap a project
controlkeel attach <host>         # attach an agent host
controlkeel attach doctor         # verify attach health
controlkeel status                # session and workspace status
controlkeel findings              # list active findings
controlkeel agents doctor         # verify agent health
controlkeel provider doctor       # verify provider config
controlkeel cloud push            # push local state to cloud
controlkeel cloud pull            # pull cloud state to local
controlkeel selfhost pack         # build self-host bundle
controlkeel benchmark run --suite host_comparison_v1  # run benchmark
```

## Drift rule

If this page disagrees with `controlkeel help`, the binary wins.
