# Large Codebase Patterns

Large repositories need scoped context, scoped execution, and explicit rollback points. Keep root guidance lean; put local conventions close to the code that uses them.

## Start in subdirectories

Do not start every agent run from repo root in a monorepo. Prefer the smallest directory that contains the task boundary.

- initialize CK work in the relevant service/package when possible
- let CK load context hierarchically from root to subdirectory
- keep the root file as pointers and critical gotchas only
- put local build/test commands in the subdirectory docs or agent guidance

## Layered context files

Use layered context instead of one giant instruction file:

- root: product invariants, global commands, security boundaries
- package/service: local architecture, test commands, naming conventions
- feature area: domain language, schema/API rules, known pitfalls

Review these files every few months. As models and host capabilities change, stale instructions become context debt.

## Scoped tests and commands

Agents should run the smallest useful validation first:

- targeted unit/integration test for the touched area
- package/service lint or typecheck
- full suite only when the change crosses boundaries or before merge

Record the chosen validation path in CK proof or task reports so future agents know what was actually checked.

## Context packing and large outputs

Use `ck_context_pack` for targeted sub-task bundles after the initial `ck_context`. Do not dump build logs, traces, benchmark exports, or subagent stdout into chat.

- use `ck_result_peek` to inspect byte ranges of large outputs
- keep large artifacts as referenced proof objects
- summarize only the decision-useful parts

## Workspace checkpoints and rollback

Use checkpoints and rollback around risky or exploratory work:

- `ck_checkpoint_create` for task milestones
- `ck_rollback` before destructive cleanup or broad edits
- git worktrees for parallel agent branches when possible

This prevents iterative loops from corrupting the primary branch and keeps unmerged work recoverable.

## LSP and symbol navigation

LSP is host/IDE-native, not a CK feature. CK's virtual workspace performs filesystem-level exploration (`find`, `grep`, `read`). For symbol-level navigation in large typed codebases:

- install language servers through the IDE or agent host
- configure exclusions for generated/build/vendor files in the host
- use LSP for references/definitions where text search is too noisy

## Extension hierarchy

Keep extension surfaces separate:

| Surface | Best for |
| --- | --- |
| Context files | durable project and local conventions |
| Skills | on-demand task workflows |
| Plugins/bundles | distributing governed host setup |
| MCP servers | external tools and data |
| Subagents | splitting exploration, execution, and review |
| Hooks | lifecycle checks, approvals, validation, debriefs |

Do not put every workflow into always-loaded context. Prefer small stable contracts plus on-demand skills.

## Organizational adoption

For large teams:

- assign ownership for CK configuration and policy upkeep
- start with approved skills and limited high-value workflows
- expand host/runtime coverage only after proof and benchmark evidence
- keep security/governance/product stakeholders in the review loop for high-impact policies
