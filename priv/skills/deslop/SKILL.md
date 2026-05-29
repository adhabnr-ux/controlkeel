---
name: deslop
description: "Clean AI slop: remove narrative comments, verbosity, hallucinated patterns, padding. Trigger: 'unslop', 'clean up AI code', 'remove slop'. Complements aislop detection."
when_to_use: "Activate ONLY when explicitly asked to clean up AI-generated slop. Do NOT auto-trigger during normal coding."
argument-hint: "[file, diff, or aislop findings to clean]"
disable-model-invocation: true
license: Apache-2.0
compatibility:
  - opencode-native
  - claude-standalone
  - cursor-native
  - codex
metadata:
  author: controlkeel
  version: "1.1"
  category: quality
  ck_mcp_tools: [ck_validate, ck_git_diff, ck_git_commit, ck_finding]
  related_skills: [deep-code-quality-review]
---

# Deslop

Remove AI-generated slop while preserving behavior. Companion to aislop scanner — aislop detects, this skill cleans.

## Do NOT use when
- Normal coding or refactoring (use `deep-code-quality-review`)
- Security issues found (use `security-review`)
- Writing new code (not applicable)

## Slop patterns (see [catalog](references/slop-patterns.md))

1. Narrative comments — describing what code obviously does
2. Unnecessary verbosity — 10 lines where 3 suffice
3. Hallucinated imports — modules not used or not existing
4. Mechanical padding — single-call wrappers, unnecessary intermediates
5. Generic error messages — "An error occurred" instead of context
6. TODO stubs with no implementation
7. Redundant type annotations — already inferred

## Subtraction rules

- **Delete, don't replace.** If a comment explains what → delete it, don't rewrite it.
- **Inline, don't redirect.** Single-call helper → inline and delete.
- **Shrink, don't reorganize.** 10-line function can be 3 → shrink, don't split.
- **Remove dead code.** Unused imports, unreachable branches.
- **Preserve intent.** Comments explaining **why** → keep. Helpers with meaningful naming → keep.

## Workflow

1. Run `ck_git_diff` to scope changes. Run `ck_validate` for aislop findings.
2. List slop patterns found. Plan removals — do not start editing until plan is clear.
3. Apply removals. Run tests after each logical group.
4. The diff must be **smaller** after cleanup, not just different.
5. Full suite must pass. Zero new failures.
6. `ck_validate` on cleaned diff. `ck_git_commit`.

## Rules

- Behavior preservation — every passing test stays passing
- No scope creep — fix slop only, do not refactor or add features
- Smaller diff — fewer lines after cleanup, not same or more

## Output

- Cleaned code with slop removed
- Full suite passing
- Commit with cleanup
