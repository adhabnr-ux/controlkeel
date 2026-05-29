# ControlKeel Cloud Readiness Tracker

> **Living document.** Updated as slices ship. Source of truth for "what's left before controlkeel.com is a real product a user can self-serve onboard to."

**Last updated:** 2026-05-29
**Authoritative branch:** `main`
**HEAD:** `05816f9` (4 commits ahead of `origin/main`, none pushed)
**Test status:** 2000 / 2000 passing

This document tracks the user-visible product gaps surfaced by the cloud-readiness audits in sessions ses_1900 and ses_2696. It complements (does **not** replace) `cloud-enterprise-roadmap.md`, which tracks backend foundations.

---

## TL;DR

The data layer is solid (tenant isolation, sync dedup, OIDC verification, audit trail, multi-tenant indices). The browser-facing onboarding is broken: a new visitor to `controlkeel.com` literally cannot sign up, create an org, configure auth, or create a workspace without first installing the CLI. **Every administrative action requires shell access.**

This doc sequences the work to close that gap.

---

## Status Snapshot

| Capability | State | Where it's blocked |
|---|---|---|
| Tenant isolation (data layer) | ✅ done | — |
| Sync engine (push/pull, dedup, redaction) | ✅ done | — |
| OIDC token exchange + JWT verification | ✅ done | — |
| LiveView auth gate (cloud mode) | ✅ done | commit `05816f9` |
| Org-scoped LiveView queries | ✅ done | commit `05816f9` |
| Mission/session ownership checks | ✅ done | commit `05816f9` |
| Sign Up / org self-serve | ❌ blocked | Finding #319 (this doc, P0) |
| Workspace creation UI | ❌ blocked | Finding #320 (this doc, P0) |
| Per-org IdP configuration UI | ❌ blocked | Finding #321 (this doc, P0) |
| Invitation auto-login | ❌ blocked | Finding #322 (this doc, P0) |
| `Mission.create_session` idempotency | ❌ bug | Finding #323 (this doc, P0) |
| Org admin UI (members/roles/budget) | ❌ blocked | Finding #324 (this doc, P1) |
| GitHub repo binding UI | ❌ blocked | Finding #324 (this doc, P1) |
| Service-account / webhook UI | ❌ blocked | Finding #324 (this doc, P1) |
| Membership-revoke broadcast | ⚠️ stale-session window | Finding #325 (this doc, P2) |
| Postgres parity CI lane | ⚠️ untested | Finding #294 (P3) |
| TypeScript SDK | ❌ missing | Finding #295 (P3) |
| Skills/hooks cloud execution model | ⚠️ design pending | Finding #293 (P3) |
| Self-host smoke test in CI | ❌ missing | Finding #297 (P3) |

---

## Already shipped

Commits in chronological order. Each closed at least one critical finding.

| Commit | What | Closed |
|---|---|---|
| `b998d6f` | Runtime mode (local / cloud / self_hosted) + endpoint URL config | runtime parity foundation |
| `74715d8` | Cloud sync ingress workspace scoping | sync push attack surface |
| `e1a30b0` | `ControlKeel.Cloud.Scope` centralized tenant-scoped helpers | CK-CLOUD-TENANT-002 prep |
| `217ae0d` | Tier 1: deprecated unscoped admin functions; scoped variants | unscoped `list_all`/`global_*` |
| `59f2107` | Tier 2: DB-enforced scoped lookups in RuntimeContext | post-fetch TOCTOU |
| `321580a` | Cross-workspace isolation regression tests | regression coverage |
| `8b53ffc` | API list endpoints scoped by service account workspace_id | CK-CLOUD-TENANT-001, CK-CLOUD-AUTH-002 |
| `c53f5ef` | LiveView + MCP tool scoping; CloudTelemetry admin gate | tier-3 LiveView leaks |
| `05816f9` | LiveAuth on_mount + AuthLive (/auth/login) + org-scoped queries + ownership checks | CK-CLOUD-LIVEVIEW-AUTH-001, CK-CLOUD-LOGIN-002, CK-CLOUD-LIVEVIEW-SCOPE-003, CK-CLOUD-MISSION-SCOPE-004, CK-CLOUD-POSTLOGIN-006 |

---

## Phase plan

Phases are sequenced by **dependency**, not preference. Each phase is one shippable slice with its own CK governance loop (plan → strong-100 → implement → tests → commit).

### P0 — Onboarding unblock (next slice)

**Outcome:** A new visitor to `controlkeel.com` can create an account, sign in, and get to their first workspace without ever opening a terminal.

| # | Item | Finding | Acceptance |
|---|---|---|---|
| P0.1 | Home page Sign In button (cloud mode only) | #319 | Anonymous visitor sees "Sign In" and "Create organization" CTAs |
| P0.2 | `/signup` LiveView (creates Org + first admin User + Membership) | #319 | Form submit → atomic create_org + create_user + accepted Membership(role=owner); session populated; redirect to `/cloud/projects` |
| P0.3 | "Create workspace" button on `/cloud/projects` | #320 | Org admin can submit (name, slug, industry, agent, budget, compliance_profile); workspace bound to current_org_id; visible in list |
| P0.4 | `/org/:slug/settings/auth` LiveView for IdP config | #321 | Owner pastes OIDC issuer/client_id/client_secret; saved via `Accounts.set_org_identity_provider`; tested round-trip with `/auth/oidc/start` |
| P0.5 | Invitation auto-login on accept | #322 | InvitationLive sets `:current_user_id` + `:current_org_id` after `accept_invitation/2`; redirect to `/cloud/projects` |
| P0.6 | `Mission.create_session` idempotency check | #323 | Repeat call with same external_id returns existing session; migration adds partial unique index on (workspace_id, external_id) WHERE NOT NULL |
| P0.7 | Tests: signup, workspace create, IdP config round-trip, invite auto-login, session idempotency | — | All green; ≥5 new tests |

**Estimated scope:** ~10 files touched, ~600-line diff. Roughly the size of slice `05816f9`.

**Dependencies:** none — these are all additive on the existing auth gate.

**Status:** ⬜ Not started

---

### P1 — Org admin UI parity

**Outcome:** A non-developer org owner can fully manage their tenant from the browser.

| # | Item | Finding | Acceptance |
|---|---|---|---|
| P1.1 | `/org/:slug/members` LiveView (list, invite, revoke, role-change) | #324 | All `Accounts.invite_member`, `revoke_membership`, role-change actions available via UI |
| P1.2 | `/org/:slug/settings/general` (name, budget, status) | #324 | Owner edits Org.name, status; budget via `Accounts.set_org_budget_cents` |
| P1.3 | `/workspaces/:id/repos` GitHub binding UI | #324 | Org admin can bind / unbind / list `WorkspaceGithubRepo` from web |
| P1.4 | `/workspaces/:id/service-accounts` | #324 | Owner can create, rotate, revoke service accounts from UI |
| P1.5 | `/workspaces/:id/webhooks` | #324 | Create, list, replay webhooks from UI |
| P1.6 | `/workspaces/:id/tool-policy` | #324 | Get / set per-workspace tool policy (inherit/allowlist/denylist) |
| P1.7 | Email delivery for invitations (real mailer, not log-only) | new | `mix help` shows mailer adapter; invitation emails actually arrive in test inboxes |
| P1.8 | Tests: every CRUD action with ownership boundary checks | — | Tenant A admin cannot manage Tenant B resources |

**Estimated scope:** ~15 LiveViews + 1 mailer module + 8 controllers updates. ~1500-line diff. **One PR per surface** to keep reviews small.

**Dependencies:** P0 must be complete (auth/signup must work first).

**Status:** ⬜ Not started

---

### P2 — Real-time enforcement + session hygiene

**Outcome:** Revoked memberships eject users immediately. Stale sessions don't linger. Mission control reflects current state.

| # | Item | Finding | Acceptance |
|---|---|---|---|
| P2.1 | PubSub broadcast on `revoke_membership` | #325 | LiveViews listen for `{:membership_revoked, user_id, org_id}`; matching sockets push_navigate to `/` |
| P2.2 | Per-request membership re-validation in cloud mode | #325 | LiveAuth on every navigation re-checks `get_active_membership`; fails closed if revoked since session start |
| P2.3 | Session timeout / sliding expiry config | new | `:session_idle_timeout_minutes` config in cloud mode; default 60 |
| P2.4 | "Sign out everywhere" action on user profile | new | Owner-initiated session invalidation |

**Estimated scope:** ~5 files. Small slice.

**Dependencies:** P0 + P1 (user/member surfaces must exist).

**Status:** ⬜ Not started

---

### P3 — Production-readiness hardening

**Outcome:** Self-host deployments work; integrators have an SDK; CI catches regressions across both DB engines; cloud-side execution model is decided.

| # | Item | Finding | Acceptance |
|---|---|---|---|
| P3.1 | Postgres parity CI lane | #294 | New CI job runs full suite against Postgres; passes |
| P3.2 | TypeScript SDK (npm: `@controlkeel/sdk`) | #295 | npm package wraps `ck_validate`, `ck_finding`, `ck_review_submit`, `ck_context`; published with semver |
| P3.3 | Self-host smoke test in CI | #297 | CI boots release against fresh DB, runs through `cloud connect --enroll`, asserts sync push/pull works |
| P3.4 | Skills/hooks cloud-execution model decision | #293 | Architectural decision recorded in `docs/cloud-execution-model.md`: hybrid (local agent + cloud state) vs cloud sandbox per session. **Decision required before implementation.** |
| P3.5 | Rate limiting per workspace on `/cloud/v1` | new | Token bucket per `db_workspace_id`; 429 on overflow |
| P3.6 | Billing/usage metering integration | new | Per-org Stripe customer; usage emitted from `Budget.spend_cents` |

**Estimated scope:** Each item is its own slice. P3.4 is a design decision, not code.

**Dependencies:** P0 + P1. P3.4 should be made before any cloud-side execution feature ships.

**Status:** ⬜ Not started

---

### P4 — Polish, docs, growth

**Outcome:** controlkeel.com is a complete commercial product.

| # | Item | Acceptance |
|---|---|---|
| P4.1 | `/pricing` LiveView | Tier pricing visible without auth |
| P4.2 | `/docs` portal | Generated from `docs/*.md` |
| P4.3 | Marketing home page (replace governance dashboard for anonymous visitors) | Anonymous visitor sees marketing copy; auth'd user sees dashboard |
| P4.4 | Status page at status.controlkeel.com | Live uptime + incident history |
| P4.5 | Support email / contact form | `support@controlkeel.com` mailbox + form |

---

## How to update this doc

When a slice lands:

1. Move the slice's checkbox from ⬜ to ✅.
2. Add a row to **Already shipped** with commit SHA and closed finding IDs.
3. Update the **Status Snapshot** table for any capability that changed state.
4. Update the **HEAD** + **Last updated** fields in the header.
5. Add the doc change to the same commit as the implementing change.

When a new gap is discovered:

1. Run `ck_finding` to record it.
2. Add a row to the relevant phase (P0–P4) with the finding ID.
3. If it blocks the current phase, mark the phase as ⏸ and note the blocker.

---

## Findings cross-index

| Finding ID | Severity | Phase | Status |
|---|---|---|---|
| CK-CLOUD-ONBOARD-001 (#319) | critical | P0.1, P0.2 | open |
| CK-CLOUD-WORKSPACE-CREATE-002 (#320) | high | P0.3 | open |
| CK-CLOUD-IDP-CONFIG-003 (#321) | high | P0.4 | open |
| CK-CLOUD-INVITE-AUTOLOGIN-004 (#322) | high | P0.5 | open |
| CK-CLOUD-SESSION-DEDUP-005 (#323) | high | P0.6 | open |
| CK-CLOUD-ORGADMIN-UI-006 (#324) | high | P1 (all) | open |
| CK-CLOUD-MEMBERSHIP-REVALIDATE-007 (#325) | medium | P2 | open |
| CK-CLOUD-DB-004 (#294) | medium | P3.1 | open |
| CK-CLOUD-SDK-005 (#295) | medium | P3.2 | open |
| CK-CLOUD-SELFHOST-007 (#297) | medium | P3.3 | open |
| CK-CLOUD-EXEC-003 (#293) | high-warn | P3.4 | open (design pending) |
| CK-CLOUD-WEB-006 (#296) | medium | P4.3 | open |

---

## Standing constraints (from CLAUDE.md)

- **No `git push` without explicit user request.** All commits stay local until the user authorizes.
- **No force-push** to `main`.
- **Cloud features stay opt-in** via `:cloud_sync_endpoint` config. Local mode must remain the default and the trust anchor.
- **Local API keys never leave the device.** `Cloud.Redactor` patterns + per-schema `sync_fields/0` allowlists enforce this at the sync boundary.
- **CK governance loop required** for non-trivial work: `ck_context` → `ck_review_submit` (code_backed_plan, strong-100) → implement → tests → `ck_finding` resolve → commit.
- **Tests must pass with `--warnings-as-errors`** before commit.

---

## Open architectural questions

These should be answered before shipping the corresponding phase.

1. **P3.4 — Skills/hooks cloud-execution model.** Two options: (a) Hybrid — agent stays on user IDE; CK governance state lives in cloud; skills/hooks fire locally and emit to cloud. (b) Cloud sandbox — ephemeral container per session, repo clone, skills/hooks run server-side. Decision needed before any cloud-side execution feature ships.

2. **P0.4 — IdP self-serve.** Two options: (a) Force every org to bring their own OIDC provider (config UI). (b) Ship a hosted fallback (Anthropic-managed Google/GitHub OAuth) for orgs without an IdP. (b) reduces friction but increases CK's own auth burden.

3. **P4.3 — Marketing site posture.** Replace the home page entirely for anonymous visitors, or keep a single dashboard that swaps content based on auth state.

---

## Owner & cadence

This doc is owned by the agent driving the cloud-parity goal (`ck_goal #672`). Reviewed at the start of every session via `ck_context`. Updates committed in the same PR as the implementing slice.
