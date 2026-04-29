# Cross-Runtime Session Continuity

Verifies that a single ControlKeel session is accessible and consistent across multiple agent runtimes — Devin Terminal, OpenCode, Claude Code, Codex CLI, and any future host.

Each runtime that completes the checklist below should mark its row in the status table and record a finding so the next host can confirm it.

---

## Status

| Runtime | Status | Verified At (UTC) | Artifacts |
|---|---|---|---|
| Devin Terminal | ✅ PASS | 2026-04-28 ~23:10 | Memory 713, 715 · Finding 338 |
| OpenCode | ✅ PASS | 2026-04-28 ~23:30 | Memory 720 · Finding 339, 344, 360 |
| Claude Code | ✅ PASS | 2026-04-28 ~23:55 | Verified memories 713–720, Finding 338 via source filter, budget $4.80/$20.00 |
| Codex CLI | ⏳ Pending | — | — |

---

## What to Verify (any new runtime)

Run these five checks against the shared session. Replace `<project_root>` with your local checkout path.

```
# 1. Session must be ID 1 and active
ck_context(project_root="<project_root>")
→ expect: session_id=1, status=active

# 2. All prior runtime memories must be searchable
ck_memory_search(query="cross-runtime-test", session_id=1, project_root="<project_root>")
→ expect: Memory IDs 713, 714, 715, 720 present

# 3. Finding shadow records filterable by source (tests the source_type/source_id fix)
ck_memory_search(query="checkpoint", source_type="finding", source_id="338", session_id=1)
→ expect: Memory 714 returned with source_type="finding"

# 4. Budget status check without cost params (tests the status-mode fix)
ck_budget(session_id=1, mode="status")
→ expect: decision=allow, spent_cents>0, remaining_session_cents>0

# 5. OpenCode artifacts visible
ck_memory_search(query="opencode continuation", session_id=1)
→ expect: Memory 720 and Finding 339/344 records present
```

After all five pass, record a finding so the next host can see your checkpoint:

```
ck_finding(
  title="<Runtime> continuation checkpoint: cross-runtime continuity verified",
  severity="info",
  description="Cross-runtime session continuity verified from <Runtime>. Memory IDs 713–720 searchable. Session 1 active. <Previous> → <Runtime> continuity PASS.",
  tags=["cross-runtime-continuity-verify"]
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
| Baseline finding IDs | 338 (Devin checkpoint), 339 (OpenCode verify), 344 (OpenCode final) |
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

All four runtimes (Devin Terminal → OpenCode → Claude Code → Codex CLI) show ✅ PASS in the Status table, each with a recorded finding. One session, one workspace, one governed memory store across all hosts.
