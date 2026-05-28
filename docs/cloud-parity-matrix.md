# Cloud parity matrix

This document is the user-perspective audit of how ControlKeel's local
CLI/governance surfaces map to its cloud control plane. It was produced as
Slice 1 of the cloud-parity-audit work and is intended as the reviewable
artifact that the remaining slices fix against.

> **Status update:** all 14 findings called out by this audit are now
> resolved (see the cross-reference table at the bottom). The narrative
> sections below describe each surface's state at audit time, including
> the ⚠️ / ❌ gaps that the linked findings closed. Read the matrix
> top-to-bottom as the original audit; trust the cross-reference table
> for current state.

Status legend:

- ✅ shipped and verified end-to-end
- ⚠️ partial — surface exists but with a documented gap
- ❌ not implemented (or implemented in name only)

## 1 — Login and session

| Surface | Storage | CLI | API / LiveView | Status |
|---|---|---|---|---|
| User accounts | `users` schema, password (Argon2) + email | n/a | `AuthController.create/2` (form login) | ✅ |
| SSO sessions | `user_tokens` (sha256 hashed) | n/a | `LoadCurrentUser` plug + session cookie | ✅ |
| Cloud workspace identity | `cloud/workspace_identity.json` (local file) | `controlkeel cloud connect [--rotate]` | n/a | ✅ |
| Enrolment with control plane | `workspace_keys` row | `controlkeel cloud connect --enroll <url>` | `POST /cloud/v1/workspaces/register` | ✅ |
| Invitation redemption | `invitations` (token hashed) | passed via `--invite` | resolved in `register/2` | ✅ |

User-visible behavior: a laptop generates a local identity, optionally posts
a proof-of-possession envelope to a control plane URL, and (if it has an
invite) gets bound to an org.

## 2 — Orgs, users, and roles

| Concept | Schema | Roles | Enforcement | Status |
|---|---|---|---|---|
| Org | `orgs` (slug, status) | n/a | unique slug, `status="active"` required | ✅ |
| Membership | `memberships` (user_id, org_id, role, status) | viewer, member, admin, owner | `Accounts.get_active_membership/2` | ✅ |
| Invitation | `invitations` (token, role, expires_at) | viewer/member/admin/owner | `Accounts.lookup_invitation/1` | ✅ |
| HTTP authz plug | n/a | `RequireOrgRole` | role_at_least?/2 ladder | ✅ |
| Cloud execution authz | n/a | viewer ❌ / member ✅ / admin ✅ / owner ✅ | `Accounts.authorize_cloud_execution/2` ([accounts.ex:917](../lib/controlkeel/accounts.ex#L917)) | ✅ |

User-visible behavior: a user belongs to one or more orgs with one role each.
Role determines which org-scoped UI they can see and whether they can
authorize a cloud run on an org workspace.

**Solo workspaces (no org)** intentionally bypass authz — this is the
local-first trust anchor.

## 3 — Projects, missions, sessions, tasks, controls

| Concept | Schema | Identity | Cross-folder dedup |
|---|---|---|---|
| Project workspace | `workspaces` (slug, org_id) | integer id + slug | slug unique per org |
| Session | `sessions` (workspace_id) | integer id | n/a — sessions are append-only |
| Task | `tasks` (session_id, title, status) | integer id | ⚠️ no content-hash dedup; identical titles in different sessions are different tasks |
| Mission control rules | `workspace_policy_sets` | per workspace | ✅ |
| Service accounts | `service_accounts` | per workspace | ✅ |
| Integration webhooks | `integration_webhooks` | per workspace | ✅ |

⚠️ **Gap CK-CLOUD-TASK-DEDUP-001**: Tasks are scoped to a session, not to a
project-level idempotency key. If the same governance scaffolding runs twice
(say, two laptops cloned from the same repo), the same brief produces two
distinct task rows. There is no de-duplication on content or external_id.
**Impact:** when one operator says "share this task with my org," the
recipient sees a new task that has no provable lineage back to the
originating local task.

## 4 — Local-to-cloud handoff

| Step | Surface | Status |
|---|---|---|
| Local task creation | `Mission.create_task/2` via brief or CLI | ✅ |
| Authorize cloud move | `Accounts.authorize_cloud_execution/2` | ✅ (CK-CLOUD-AUTHZ-001 fixed) |
| Build cloud payload | `CLI.build_cloud_payload/2` | ⚠️ thin |
| Persist run package | `Cloud.RunPackage` (status, scopes, callback_token_hash) | ✅ |
| Hand to runtime | runtime-specific dispatch (out of scope) | ❌ not implemented for any runtime |
| Runtime callback | `CloudRuntimeCallbackController` | ✅ |
| Status terminal-reject | `RuntimeContext.update_status/2` | ✅ |

⚠️ **Gap CK-CLOUD-PAYLOAD-001**: `build_cloud_payload/2` only ships
`task_title`, `validation_gate`, and `note`. **No git remote, branch, commit
SHA, repo URL, file list, or local workspace fingerprint.** A cloud runtime
that receives this payload has no provable way to know which code revision
the task is about. The runtime must therefore either (a) trust a side
channel, or (b) refuse to operate, defeating the round-trip handoff.

❌ **Gap CK-CLOUD-DISPATCH-001**: There is no runtime dispatcher.
`RunPackage` rows are created in `pending` and never move forward on their
own. A separate worker, webhook, or operator-driven trigger is needed to
hand the package to an actual runtime. This is acknowledged in the roadmap
but not implemented.

## 5 — Local↔cloud workspace identity

| Concept | Storage | Wired by |
|---|---|---|
| Cloud workspace ULID | `workspace_keys.workspace_id` (e.g. `ws_abc...`) | CLI `cloud connect` |
| Mission workspace integer id | `workspaces.id` | server-side fixtures / admin UI |
| Link column | `workspace_keys.mission_workspace_id` (added in slice 3) | ⚠️ only tests |
| Lookup | `WorkspaceKeyRegistry.fetch_by_mission_workspace/1` | LiveView preload only |

⚠️ **Gap CK-CLOUD-ENROLL-LINK-001**: The `mission_workspace_id` column,
indexes, and `fetch_by_mission_workspace/1` exist but **nothing in
production code populates the column**. The HTTP enrolment handler
([cloud_workspace_controller.ex:101](../lib/controlkeel_web/controllers/cloud_workspace_controller.ex#L101))
doesn't accept a `mission_workspace_id` parameter; the CLI enrol path
([cli.ex:1966](../lib/controlkeel/cli.ex#L1966)) doesn't send one. Every
production row therefore has `mission_workspace_id = NULL`, and the new
"Project" column in `CloudProjectsLive` always shows `—`.

The design choice for fixing this is open:
1. **Invitation-binding**: add `mission_workspace_id` to `invitations`. When
   an operator pre-provisions a project workspace they also generate an
   invite scoped to it; redemption auto-links the enrolled key.
2. **Enrolment param**: extend the registration envelope with a
   `mission_workspace_slug` the laptop sends; server upserts the workspace
   and links the key.
3. **Server-side upsert**: the server creates a `workspaces` row with a
   derived slug at enrolment time and links it.

Each requires schema migration + design alignment + tests; none should be
done without review.

## 6 — Git / GitHub integration

| Surface | Implementation | Status |
|---|---|---|
| Govern install scaffolding | `Governance.install_github_scaffolding/2` writes `.github/workflows/*.yml` and `.github/controlkeel/README.md` | ✅ (file scaffolding only) |
| GitHub App / webhook | n/a | ❌ |
| PR governance round-trip | n/a | ❌ |
| Commit SHA capture on findings | `Mission` regression schema accepts `commit_sha` | ⚠️ accepted, not captured |
| Repo URL on run packages | `RunPackage` has no `repo_url`, `branch`, `commit_sha` columns | ❌ |

⚠️ **Gap CK-CLOUD-GIT-001**: `govern install github` is purely local
file generation — it does not register a GitHub App, does not enrol a
webhook, and does not exchange identity with GitHub. The workflows it
writes will run inside the user's repo using public GitHub Actions, but
there is no two-way binding between a ControlKeel org/workspace and a
GitHub repo. From the user perspective, "ControlKeel knows my GitHub repo"
is currently false.

## 7 — Cloud execution permission and observability

| Concern | Implementation | Status |
|---|---|---|
| Org/role authz on cloud run | `Accounts.authorize_cloud_execution/2` | ✅ |
| Callback token lifecycle | hashed, valid until terminal status | ✅ |
| `CloudProjectsLive` shows enrolled keys | yes | ✅ |
| `CloudProjectsLive` shows run-package status | ❌ | ❌ |
| `CloudProjectsLive` shows findings/proofs from cloud runs | ❌ | ❌ |
| `CloudProjectsLive` shows callback history | ❌ | ❌ |
| Telemetry ingestion (signed ed25519) | `Cloud.AuthToken.verify/1` | ✅ |
| Event deduplication | `Cloud.Ingestion.upsert/2` by `event_id` | ✅ |

⚠️ **Gap CK-CLOUD-OBS-001**: The cloud LiveView surfaces enrolment metadata
and raw telemetry event counts, but never surfaces the actual round-trip
units of cloud work: run packages, their statuses, the findings they
produced, the proofs they referenced. The user cannot ask "what did my
cloud do for me" from the UI.

## 8 — Findings, cases, proofs, policies, skills

| Concept | Schema | Cross-org isolation | Cloud round-trip |
|---|---|---|---|
| Findings | `findings` (session_id, workspace_id) | ✅ — workspace_id filter | ❌ no cloud-originated finding ingestion |
| Cases (security) | `security_cases` | ✅ | ❌ |
| Proofs | `proofs` | ✅ | ⚠️ `RunPackage.proof_refs` accepts ids but no proof is generated on completion |
| Policies | `workspace_policy_sets`, `tool_policies` | ✅ | ❌ no cloud policy distribution |
| Skills | files on disk (`.controlkeel/skills/*`) | n/a (local) | ❌ no cloud sync |

⚠️ **Gap CK-CLOUD-FINDING-001**: Findings are written by the local agent or
by `Cloud.Ingestion` for telemetry. There is no path from a runtime
callback (`CloudRuntimeCallbackController.update/2`) to creating a finding
in the originating workspace. A cloud-run task that discovers a security
issue cannot persist that issue back to the local finding stream.

## 9 — Multi-org, multi-user isolation

| Boundary | Enforced by | Tested |
|---|---|---|
| Workspace ↔ org | `workspaces.org_id` foreign key, `RequireOrgRole` plug | ✅ |
| Cloud key ↔ org | `workspace_keys.org_id`, `WorkspaceKeyRegistry.list_for_org/1` | ✅ |
| Telemetry events ↔ workspace | `received_telemetry_events.workspace_id` + auth token signature | ✅ |
| Run package ↔ workspace | `cloud_run_packages.workspace_id` foreign key | ✅ |
| Cross-org findings leak | n/a — findings are workspace-scoped | ✅ schema; ⚠️ no integration test |
| Cross-org task share | n/a — tasks scoped to session.workspace | ✅ |

⚠️ **Gap CK-CLOUD-XORG-TEST-001**: Cross-org isolation is enforced by
schema and plugs, but there is no integration test that proves a user in
org A *cannot* observe a task, finding, run package, or telemetry event
from org B. The pieces look correct but the regression-prevention test
doesn't exist.

## 10 — Metrics

| Metric | Surface | Status |
|---|---|---|
| Budget spend (session/daily) | `ck_budget` MCP tool | ✅ |
| Telemetry event counts | `CloudProjectsLive` show view | ✅ |
| Run package counts by status | n/a | ❌ |
| Findings counts by severity | local-only UI | ⚠️ no cloud surface |
| Token overhead audit | `ck_budget include_token_overhead` | ✅ |

## 11 — Naming and identification consistency

| Concept | Identifier used in code | Identifier shown to user |
|---|---|---|
| Cloud workspace | `ws_<ulid>` (string) | same |
| Mission workspace | integer id + slug | slug |
| Org | integer id + slug | slug |
| User | integer id + email | email |
| Task | integer id + title | title |
| Session | integer id | usually invisible |
| Run package | integer id | ❌ no user-facing identifier |
| Finding | integer id + rule_id | rule_id |

⚠️ **Gap CK-CLOUD-NAMING-001**: Run packages are user-visible artifacts
(they represent a cloud-run task) but have no stable user-facing
identifier — only an integer primary key. The CLI prints "Run package
created: id=42" which is not useful for the user to reference later.
Consider a `pkg_<ulid>` external ID.

## Cross-reference: audit findings

All 14 findings from the cloud parity audit are resolved. The matrix
above still describes each surface from the user's perspective; the
table below tracks each finding to the commit/slice that closed it.

| Rule | Severity | Resolution |
|---|---|---|
| CK-CLOUD-AUTHZ-001 | high | `Accounts.authorize_cloud_execution/2` gates `RuntimeContext.create_package/1`; CLI `--user-id`. |
| CK-CLOUD-PAYLOAD-001 | high | `cloud_run_packages.repo_url/branch/commit_sha` captured by `build_cloud_payload/2` via `git rev-parse` / `git remote get-url`; `--repo-url/--branch/--commit-sha` overrides. |
| CK-CLOUD-DISPATCH-001 | high | `RuntimeDispatcher` behavior + `Manual` default; `:cloud_dispatchers` config registry; `--dispatch` CLI flag. |
| CK-CLOUD-TOKEN-001 | medium | `RunPackage` + `RuntimeContext` moduledocs aligned with valid-until-terminal semantics. |
| CK-CLOUD-ID-001 | medium | `workspace_keys.mission_workspace_id` + `WorkspaceKeyRegistry.fetch_by_mission_workspace/1`; LiveView preloads the link. |
| CK-CLOUD-ENROLL-LINK-001 | medium | Invitation-binding: `memberships.mission_workspace_id` + `Accounts.invite_member(..., mission_workspace_id: …)` + `CloudWorkspaceController` threads the binding through enrollment. |
| CK-CLOUD-OBS-001 | medium | `CloudProjectsLive` show page renders a Cloud run packages card. |
| CK-CLOUD-FINDING-001 | medium | `CloudRuntimeCallbackController` accepts `findings[]`; `RuntimeContext.ingest_findings/2` persists each with cloud provenance metadata. |
| CK-CLOUD-TASK-DEDUP-001 | medium | `tasks.external_id = task_<ulid>`, caller-overridable for cross-clone lineage. |
| CK-CLOUD-GIT-001 | medium | `workspace_github_repos` schema + Mission API + `controlkeel govern bind/unbind/list github`; bindings ride the cloud payload. |
| CK-CLOUD-DOC-001 | low | `CloudTelemetryController` moduledoc describes signed ed25519 AuthToken. |
| CK-CLOUD-UI-001 | low | Missing `<td>` for Project column + awkward `if/do:` pipes. |
| CK-CLOUD-XORG-TEST-001 | low | `test/controlkeel/cloud/cross_org_isolation_test.exs` pins authz, list_for_org, list_for_workspace, LiveView index, LiveView show. |
| CK-CLOUD-NAMING-001 | low | `cloud_run_packages.external_id = pkg_<ulid>`, surfaced in CLI, LiveView, callback response. |

## What's still genuinely out of scope

These are real future work, not gaps from the audit:

- **Real GitHub App credential exchange.** The `workspace_github_repos`
  schema is ready (nullable `installation_id`, free-form metadata) but
  no App ID / webhook secret flow is implemented. Needs an operator
  decision on App vs. Actions-only and credentials in hand.
- **Runtime-specific dispatchers** for Devin, Open SWE, Cloudflare
  Workers, etc. The `RuntimeDispatcher` behavior is the seam; concrete
  implementations are runtime-by-runtime and depend on which one ships
  first.
- **Content-hash task dedup.** `external_id` covers explicit-lineage
  sharing; auto-detecting "same brief on two laptops" by content hash
  is a separate decision.
- **PR governance round-trip.** Needs the GitHub App work above before
  it can land webhooks/PR-comments/check-runs.
