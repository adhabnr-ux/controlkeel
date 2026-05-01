---
name: security-review
description: "Run a structured security review before marking a task done. Use this for code, config, architecture, or release reviews that need OWASP, baseline pack, and domain-pack coverage."
when_to_use: "Use before merging, deploying, or signing off on code, config, or architecture changes. Activate when reviewing auth, input handling, secrets, or third-party dependencies."
argument-hint: "[file, PR, or area to review]"
license: Apache-2.0
compatibility:
  - codex
  - claude-standalone
  - claude-plugin
  - copilot-plugin
  - github-repo
  - open-standard
metadata:
  author: controlkeel
  version: "2.1"
  category: security
  ck_mcp_tools:
    - ck_validate
    - ck_context
    - ck_finding
    - ck_regression_result
  related_skills:
    - agent-pattern-verification
---

# Security Review Skill

Use this skill before closing a task, approving a proof bundle, or reviewing a risky diff.

## Review flow

1. Call `ck_context` to load the domain pack, risk tier, open findings, instruction hierarchy, and design-drift signals.
2. Check if agent frameworks are detected in workspace context. If agent frameworks (LangGraph, CrewAI, AutoGen, LangChain) are present, activate the agent-pattern-verification skill for additional agent-specific checks.
3. Run `ck_validate` on the relevant code or config slices, including trust-boundary metadata when the proposed action was influenced by web, tool, skill, or mixed-provenance content.
4. Walk the review checklist in [references/review-checklist.md](references/review-checklist.md).
5. Persist any missed issue with `ck_finding`.
6. If external security or regression systems produce exploit or browser evidence, record that through `ck_regression_result` when it affects release readiness.
7. Summarize blockers, warnings, and follow-up proof requirements.

## Agent Pattern Integration

When agent frameworks are detected in the workspace context, this skill automatically includes agent-specific pattern checks:

- **Loop Safety**: Detects `while True` without break, recursive calls without depth limits
- **Retry Limits**: Validates retry decorators have explicit stop conditions
- **Tool Registry**: Cross-references tool definitions with prompt references
- **Context Size**: Monitors system prompt and tool description token counts
- **Graph Cycles**: Analyzes LangGraph graphs for unreachable END nodes

These checks complement the baseline security review with agent-specific anti-pattern detection.
