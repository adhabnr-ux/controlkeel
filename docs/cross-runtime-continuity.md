# Cross-Runtime Session Continuity

Verifies that a single ControlKeel session is accessible and consistent across multiple agent runtimes — Devin Terminal, OpenCode, Claude Code, Gemini CLI, Codex CLI, **Cursor**, **Antigravity**, and any future host.

Each runtime that completes the checklist below should mark its row in the status table and record a finding so the next host can confirm it.

---

## Status

| Runtime | Status | Verified At (UTC) | Artifacts |
|---|---|---|---|
| Devin Terminal | ✅ PASS | 2026-04-28 ~23:10 | Memory 713, 715 · Finding 338 |
| OpenCode | ✅ PASS | 2026-04-28 ~23:30 | Memory 720 · Finding 339, 344, 360 |
| Claude Code | ✅ PASS | 2026-04-28 ~23:55 | Verified memories 713–720, Finding 338 via source filter, budget $4.80/$20.00 |
| Gemini CLI | ✅ PASS | 2026-04-29 ~00:15 | Memory 714-720 searchable, Finding 338 via source filter, budget status PASS |
| Cursor | ✅ PASS | 2026-04-29 ~00:56 UTC | Finding 362 · MCP five-check run from Cursor agent; `bin/controlkeel-mcp` initialize JSON-RPC OK |
| Antigravity | ✅ PASS | 2026-04-29 ~01:02 UTC | Finding 363 · MCP five-check run from Antigravity agent; `bin/controlkeel-mcp` initialize JSON-RPC OK |
| Codex CLI | ✅ PASS | 2026-04-29 ~04:07 UTC | Finding 369 · MCP five-check run from Codex agent; `.codex/config.toml` and `bin/controlkeel-mcp` initialize JSON-RPC OK |

---

## What to Verify (any new runtime)

**Prerequisite:** Your host must load ControlKeel MCP for this checkout so the tools below run against the same `project_root` (install, attach, and host-specific wiring are **not** repeated here—see `AGENTS.md` and your client’s MCP documentation).

Replace `<project_root>` with your local checkout path in tool arguments.

Optional sanity check that the workspace `bin/controlkeel-mcp` launcher speaks JSON-RPC on stdout (run from the repo root):

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"0"}}}' \
  | CK_PROJECT_ROOT="<project_root>" bin/controlkeel-mcp 2>/dev/null | head -c 500
# expect: JSON result with serverInfo.name "controlkeel"
```

If this check is run from a restricted sandbox and fails with a Mix PubSub `:eperm` socket error, rerun it from the trusted host environment. The launcher is local-stdio MCP, but this source checkout uses `mix ck.mcp`, and Mix may need to open its local PubSub socket while booting.

For Codex CLI specifically, also verify the repo-local attach surface before marking the host complete:

- `.codex/config.toml` registers `[mcp_servers.controlkeel]` with `bin/controlkeel-mcp`.
- `.codex/hooks.json` and `.codex/hooks/` exist for CK lifecycle hooks.
- `.codex/commands/`, `.codex/agents/`, and `.codex/skills/` are present.
- `.agents/skills/` compatibility copies are present.
- `mix ck.attach doctor --project-root <project_root>` lists `codex-cli` under attached agents.

Run these five checks against the shared session:

```
# 1. Governed session must be session 1 (context load succeeds)
ck_context(project_root="<project_root>", session_id=1, detail_level="compact")
→ expect: top-level `session_id` is `1` and `bootstrap_status.auto_bootstrapped` is true (session row does not expose a separate `status=active` field in this payload)

# 2. Baseline typed memories must be searchable (FTS ranking varies by query)
ck_memory_search(query="cross-runtime-test", session_id=1, project_root="<project_root>")
→ expect: memory IDs **714**, **715**, and **720** among the hits
ck_memory_search(query="Devin Terminal", session_id=1, project_root="<project_root>")
→ expect: memory **713** among the hits (713 is the Devin-started baseline; it may rank below other rows on the narrow `cross-runtime-test` query alone)

# 3. Finding shadow records filterable by source (tests the source_type/source_id fix)
ck_memory_search(query="checkpoint", source_type="finding", source_id="338", session_id=1, project_root="<project_root>")
→ expect: Memory 714 returned with source_type="finding"

# 4. Budget status check without cost params (tests the status-mode fix)
ck_budget(session_id=1, mode="status", project_root="<project_root>")
→ expect: decision=allow, spent_cents>0, remaining_session_cents>0

# 5. OpenCode artifacts visible
ck_memory_search(query="opencode continuation", session_id=1, project_root="<project_root>")
→ expect: Memory 720 and Finding 339/344 records present
```

After all five pass, record a finding so the next host can see your checkpoint (MCP-required fields shown; optional `title` / `metadata` are supported):

```
ck_finding(
  session_id=1,
  category="integration",
  severity="info",
  rule_id="cross-runtime-continuity-verify-<runtime_slug>",
  plain_message="Cross-runtime session continuity verified from <Runtime>. Baseline memories 713–720 reachable via search. Session 1 bound. <Previous> → <Runtime> continuity PASS.",
  title="<Runtime> continuation checkpoint: cross-runtime continuity verified",
  metadata={"tags": ["cross-runtime-continuity-verify"]}
)
```

Then update the Status table above with your row.

---

## Shared State Reference

| Item | Value |
|---|---|
| Session ID | 1 |
| Workspace ID | (resolved via `ck_context`) |
| Baseline memory IDs | 713 (checkpoint), 714 (finding shadow), 715 (decision), 720 (OpenCode decision) |
| Baseline finding IDs | 338 (Devin checkpoint), 339 (OpenCode verify), 344 (OpenCode final), 363 (Antigravity verify), 369 (Codex CLI verify) |
| Budget cap | $20.00 session / $20.00 daily |

---

## Bugs Found and Fixed During This Verification

Both fixes shipped 2026-04-28, 973 tests 0 failures, Review 179 approved.

### 1 — Finding shadow records not filterable by source
`ck_memory_search` had no `source_type`/`source_id` parameters. Extended the full stack: MCP tool → SQLite store → pgvector store → protocol schema. Finding shadow records are now directly queryable without post-filtering.

### 2 — No read-only budget check
`ck_budget mode=estimate` required cost inputs (`estimated_cost_cents` or `provider`/`model`/tokens), so agents calling it with only `session_id` to check headroom got MCP error -32602. Added `mode=status` which accepts only `session_id` and returns current spend, budgets, and a block/warn/allow decision.

---

## Success Criterion

Every runtime listed in the Status table should show ✅ PASS, each with a recorded finding for the five-check continuity run, before that host is treated as verified for cross-runtime dogfood. One session, one workspace, one governed memory store across all participating hosts. Codex CLI is verified by Finding 369.
