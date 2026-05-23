# Cloud / Team / Enterprise Roadmap

ControlKeel is **local-first by design**. Cloud and team features are strictly optional additions that preserve the local trust anchor. This document describes the roadmap for teams and organizations that need shared governance surfaces beyond a single laptop.

## North star

ControlKeel Cloud is the governed control plane for teams running agents across local and cloud runtimes.

The enterprise buyer gets one thing: **every agent, tool call, approval, cost, finding, proof, and runtime handoff is governed in one place.**

Local mode remains the default and the trust anchor. Cloud features layer on top, never replace it. CK should govern agent work wherever it runs — laptop, CI, cloud coding agent, enterprise hosted runtime, or self-hosted cluster.

## Existing code-backed foundations

These surfaces already exist in the codebase and provide the structural scaffolding for cloud/team features:

| Surface | Code location | What it provides |
| --- | --- | --- |
| Runtime mode | `ControlKeel.Runtime` | `:local` / `:cloud` mode switch, bus selection, `cloud_repo_enabled?` |
| Cloud repo | `ControlKeel.CloudRepo` | Postgres adapter stub for cloud-mode persistence |
| Bus abstraction | `ControlKeel.Bus` + `Bus.Local` + `Bus.Nats` | Pluggable pub/sub: local ETS bus for single-node, NATS for distributed (`CONTROLKEEL_NATS_URL`) |
| Service accounts | `ControlKeel.Platform.ServiceAccount` | Named service accounts with hashed tokens and workspace scoping |
| OAuth scopes | `ControlKeel.ProtocolAccess` | Typed protocol scope model (`mcp:access`, `context:read`, `validate:run`, etc.) |
| Hosted MCP/A2A | `ControlKeel.ProtocolInterop` | Hosted MCP gateway (`POST /mcp`), A2A agent-card discovery, scoped tool filtering |
| Platform APIs | `ControlKeel.Platform` | Task graphs, task runs, policy sets, webhooks, integration delivery |
| Telemetry handler | `ControlKeel.Analytics.TelemetryHandler` | Local telemetry event emission and persistence |
| Runtime config | `config/runtime.exs` | Cloud-mode config (Postgres, NATS, `DATABASE_URL`) |
| Local analytics | `ControlKeel.Analytics` | Local persistence of governance analytics |
| Runtime catalog | `AgentIntegration.catalog/0` | Attach clients, headless runtime exports, hosted/cloud agent surfaces |

These foundations are real shipped code, not aspirational stubs. They mean the cloud roadmap is about wiring existing surfaces together behind feature flags and opt-in controls, not about building from scratch.

## Trust and privacy model

This needs to be explicit everywhere:

| Principle | What it means in practice |
| --- | --- |
| **No telemetry by default** | ControlKeel does not phone home. All governance evidence stays local unless the operator explicitly enables sync. |
| **Opt-in telemetry levels** | Teams choose how much evidence leaves the local node. Levels are cumulative and strictly increasing. |
| **Local trust anchor** | Even with cloud sync enabled, the local database remains the primary source of truth. Cloud is a replica and coordination surface, not the authority. |
| **Service-account boundaries** | Remote access is scoped through named service accounts with fine-grained protocol scopes, not blanket admin keys. |
| **Evidence redaction** | Telemetry sync applies the same redaction rules as proof bundles and audit exports before data leaves the node. |
| **Telemetry is evidence, not authority** | Synced telemetry is treated as observability input for dashboards and audit. It does not directly rewrite policy, router, prompt, or skill artifacts. |

### Opt-in telemetry levels

| Level | What syncs | When to use |
| --- | --- | --- |
| **Health** | Heartbeat, version, workspace ID, install/attach success metrics | Fleet monitoring; no governance content |
| **Governance metadata** | Finding counts/severity, approval state, budget/cost summaries, task/session IDs (redacted) | Team dashboards; no source code or diffs |
| **Evidence sync** | Proof bundles, validation summaries, review packets, memory citations, redacted trace packets, regression results | Cross-host coordination; shared audit trail |
| **Full enterprise audit** | Complete session transcripts (redacted), benchmark results, policy change history, org-controlled retention | Regulated environments; SOC 2 / GDPR compliance audit |

Level selection is per-workspace and requires explicit operator confirmation. There is no automatic escalation. Never make cloud telemetry required for core local CK.

## Enterprise package modes

CK should eventually ship in distinct packaging modes, each targeting a different deployment topology:

| Mode | Description |
| --- | --- |
| **Local single-user** | Current default. SQLite + local ETS bus + packaged binary. No cloud dependency. |
| **Team cloud SaaS** | Hosted CK with team workspace, shared MCP gateway, team approvals, org budgets. |
| **Enterprise self-host** | CK deployed behind enterprise firewalls. Postgres + NATS JetStream + object storage. SSO/RBAC. |
| **Hybrid** | Local agents + hosted governance. Agents run locally; findings, proofs, and approvals sync to hosted CK. |
| **Private cloud** | Hosted MCP gateway + customer-owned DB/NATS. CK orchestrates but data stays in customer infrastructure. |

All modes share the same governed MCP surface, validation engine, and proof/memory model. The difference is where the authority node runs and how far evidence syncs.

## Roadmap branches

### 1. Opt-in telemetry and evidence sync

Current local observability is good. Cloud should add a sync layer, not replace it.

**CLI surface preview:**

```bash
controlkeel cloud connect
controlkeel telemetry status
controlkeel telemetry enable --level health|governance|evidence
```

**Build:**
- Signed workspace identity
- Redaction policy before upload
- Event envelope schema
- Local queue + retry
- Server-side ingestion

**First useful slice:**
- Upload only health + version + install/attach success metrics
- Dashboard: install-to-first-finding funnel across opted-in workspaces

**Dependencies:** telemetry level configuration UI, redaction pipeline, cloud endpoint auth.

### 2. Hosted MCP gateway

Docs already correctly frame hosted MCP as enterprise gateway/root of trust. Expand from "CK tools over hosted MCP" to a full team gateway.

**Build:**
- Org-scoped MCP gateway
- Service accounts, user accounts, team accounts
- Scoped tool catalogs
- Downstream MCP server registry
- Per-tool policy checks
- Audit log for every tool call
- Optional proxy/tunnel to internal MCP servers

**First useful slice:**
- Hosted MCP supports CK tools with org/workspace auth
- Dashboard shows tool calls, denied calls, scopes, workspace

**Later:**
- Register downstream MCP servers
- Route through CK gateway
- Enterprise allowlists and DLP/redaction

**Dependencies:** multi-tenant workspace isolation, gateway routing config, per-team scope policies.

### 3. Team workspaces and multi-user approvals

Current model has workspaces but not full team collaboration.

**Build:**
- Users, orgs, memberships, roles
- Workspace members
- Review assignments
- Approval policies and reviewer quorum
- Human approval SLA / audit log

**First useful slice:**
- Invite users to a workspace
- Review packet assigned to a teammate
- Approval records who approved/denied

**Enterprise slice:**
- Policy: "security findings need security reviewer"
- Policy: "prod deploy requires 2 approvals"
- Policy: "schema migration requires owner approval"

**Dependencies:** team identity model, role-based review routing, notification surfaces.

### 4. Org-level spend controls

Current budget is session/daily and proxy-aware. Enterprise needs org budget policy.

**Build:**
- Org/workspace/team budget caps
- Provider/model allowlists
- Quota windows
- Per-agent/runtime spend attribution
- Spend alerts/webhooks

**First useful slice:**
- Org budget table + workspace rollup
- Block hosted MCP/provider calls when org cap exceeded
- Dashboard by workspace/session/agent/model

**Dependencies:** org/team hierarchy model, budget allocation API, alert routing.

### 5. Cloud-agent runtime loop

Major players already have cloud agents. CK should support them as first-class runtime surfaces.

Current model already has headless runtime export, service-account credentials, hosted MCP/A2A, and task run state. Make this product-grade:

**Build:**
- Cloud agent registration
- Runtime callback URLs
- Run package download
- Proof/result upload
- Task status sync
- Hosted MCP credentials per run
- Runtime event stream

**First useful slice:**
- "Run this task on cloud runtime" creates service account + package + waiting callback
- Cloud runtime posts result/proof back
- Mission Control shows lifecycle

**Cloud-agent targets (already in support-matrix as `headless_runtime`):**
- Devin (`controlkeel runtime export devin`)
- Open SWE (`controlkeel runtime export open-swe`)
- Warp Oz (`controlkeel runtime export warp-oz`)
- Executor (`controlkeel runtime export executor`)
- Virtual Bash (`controlkeel runtime export virtual-bash`)
- Cloudflare Workers (`controlkeel runtime export cloudflare-workers`)
- Codex app-server style clients
- Enterprise internal agents

**Dependencies:** cloud-mode persistence (CloudRepo), NATS bus for coordination, remote task dispatch.

### 6. NATS JetStream multi-node coordination

Current NATS is just pub/sub. Roadmap wants JetStream-backed cloud coordination.

Use JetStream for:
- Durable task queues
- Webhook delivery retry
- Telemetry ingestion
- Cloud agent callbacks
- Benchmark/eval jobs
- Proof processing
- Budget/circuit-breaker events

**First useful slice:**
- Durable event envelope
- Local bus remains default
- Cloud mode uses NATS JetStream
- One worker consumes task-run events idempotently

**Critical design:**
- Append facts first, projections second, side effects after governed state
- Idempotency keys everywhere

**Dependencies:** NATS JetStream deployment, event schema versioning, consumer group management.

### 7. Enterprise self-host

Enterprise customers will want CK fully cloud-capable but not necessarily SaaS-only.

**Build:**
- SSO/SAML/OIDC integration
- RBAC
- Air-gapped install artifacts
- Compliance report exports (SOC 2, GDPR)
- Managed policy packs for regulated verticals
- Admin UI
- Retention/redaction controls
- Telemetry disabled by default

**Infrastructure requirements:**
- Postgres
- NATS JetStream
- Object storage for proof bundles
- SSO integration

**Dependencies:** SAML/OIDC integration, air-gapped install artifacts, compliance report templates.

## Phased plan

### Phase 1 — Cloud foundation, no trust leap

Make docs explicit, harden the cloud-mode boundary, and confirm existing surfaces work end-to-end.

- Make docs explicit: local-first + cloud-optional (done — this doc)
- Add opt-in telemetry levels to observability docs (done)
- Add cloud mode status/doctor command
- Confirm hosted MCP/A2A/service-account flows work end-to-end
- Add cloud capability markers to runtime surfaces in [support-matrix.md](support-matrix.md)

This phase proves the trust model and the existing code surfaces in production with zero new cloud dependency.

### Phase 2 — Opt-in telemetry and evidence sync

Ship the narrowest useful cloud loop.

- `controlkeel cloud connect` with workspace identity
- `controlkeel telemetry enable --level health|governance`
- Redaction pipeline before upload
- Dashboard: install-to-first-finding funnel, finding counts, approval state

Start with health + governance metadata only. No evidence sync yet.

### Phase 3 — Hosted MCP gateway MVP

Extend hosted MCP to serve as a team's single blessed entrypoint.

- Org/workspace-scoped hosted MCP
- Tool-call audit log
- Scope-filtered tool catalogs
- Gateway dashboard
- Per-tool policy enforcement

### Phase 4 — Team workspace MVP

Add multi-user collaboration on top of the gateway.

- Users/orgs/memberships
- Workspace invite/list
- Review assignment and team approval audit
- Org budget rollup
- Shared typed memory and policy sets

### Phase 5 — Cloud-agent runtime loop

Enable agents to run against a shared cloud-hosted CK instance.

- Runtime registration for Devin, Open SWE, Warp Oz, Executor, CF Workers, Codex app-server, enterprise internal agents
- Task package handoff with service-account credentials
- Callback/result/proof ingestion
- Mission Control lifecycle UI
- Cloud-agent status and retry handling

### Phase 6 — Enterprise control plane

Complete the enterprise surface.

- SSO/RBAC (SAML/OIDC)
- Org policy sets
- Advanced budgets with quota windows
- Audit exports and retention/redaction controls
- Self-host packaging
- NATS JetStream durable queues for multi-node coordination
- Idempotency and replay for scalable observability projections

## Open questions and decisions owed

These need explicit decisions before Phase 2 code lands. Each one shapes downstream phases, so leaving them implicit creates rework.

| Question | Why it matters | Owner | Target decision phase |
| --- | --- | --- | --- |
| Single Phoenix app with `Runtime.mode` flag vs. dedicated cloud control-plane service? | Determines deploy topology, schema layout, and whether `CloudRepo` is a sibling repo or a separate app boundary. | architecture | Phase 1 |
| Workspace identity: signed device key, OAuth client per workspace, or both? | Wire-level auth contract for `controlkeel cloud connect`. Downstream telemetry, hosted MCP, and cloud-agent flows all hang off this. | security | Phase 1 |
| Telemetry event envelope schema (versioning, idempotency keys, redaction marker placement)? | Stable wire format unblocks Phase 2 ingestion and any third-party dashboard consumers. Schema changes after launch are expensive. | platform | Phase 2 |
| Org/user/membership data model — extend `Platform.ServiceAccount` or new `accounts` context? | Choice locks the migration path and decides whether service accounts and user accounts share a token model. | platform | Phase 3 |
| Hosted MCP multi-tenancy: workspace-scoped tokens only, or org + workspace hierarchy in protocol scopes? | Affects scope strings exposed in `ProtocolAccess` and downstream RBAC. | platform | Phase 3 |
| Storage for proof bundles in cloud mode: Postgres BYTEA, S3-compatible object store, or external blob service? | Drives Phase 5 self-host requirements and DLP/redaction surface area. | infra | Phase 5 |
| NATS JetStream consumer durability strategy: per-workspace streams vs. shared streams with subject filters? | Determines blast radius of poison messages and back-pressure isolation. | infra | Phase 6 |

Record each decision through `ck_review_submit` as it lands, link the review ID back into this table.

## Phase 1 first-PR scope: `controlkeel cloud doctor`

Phase 1 lists "add cloud mode status/doctor command" as the only item without existing code. Below is the concrete first-PR spec so it can be picked up immediately.

**Goal:** A read-only diagnostic that proves the cloud-mode boundary works end-to-end before any sync feature ships.

**Surface:**

```bash
controlkeel cloud doctor
```

**Reports:**

- `Runtime.mode` value and source (config vs. env override)
- `CloudRepo` configured? (DATABASE_URL present + reachable in cloud mode)
- Bus selection: `Bus.Local` vs `Bus.Nats`, and NATS reachability if configured
- Service-account count and oldest unused token
- Hosted MCP route registered? (`POST /mcp` reachable on configured host)
- A2A agent-card endpoint reachable?
- Telemetry sync status: `disabled` (always, until Phase 2 lands)

**Non-goals:**

- No mutation. No token issuance. No remote calls beyond local-network probes already configured.
- Does not send telemetry. Does not assume cloud connectivity.

**Acceptance:**

- Command exits 0 with structured report when running in local mode and reports all checks "not applicable".
- Command exits non-zero only on detected misconfiguration (e.g., `Runtime.mode == :cloud` but `DATABASE_URL` unset).
- New test in `test/controlkeel/cli_runtime_test.exs` covers both local and cloud-mode probes via stubs.
- No new runtime dependencies.

This becomes the trust-anchor command for every later phase — it should keep working unchanged as Phase 2+ adds new surfaces.

## Per-phase acceptance gates

Each phase ships behind explicit gates. A phase is not "done" until all of its gates pass and a `ck_review_submit` packet captures the evidence.

| Phase | Acceptance gates |
| --- | --- |
| **Phase 1 — Cloud foundation** | `controlkeel cloud doctor` ships; hosted MCP/A2A end-to-end test green in CI; docs land; no findings open against trust-boundary or untrusted instruction rules. |
| **Phase 2 — Telemetry sync** | `controlkeel cloud connect` issues a signed workspace identity; `controlkeel telemetry enable --level health` posts at least one health event end-to-end; redaction pipeline has unit tests; dashboard renders install-to-first-finding funnel for a seeded workspace. |
| **Phase 3 — Hosted MCP gateway MVP** | Hosted MCP rejects requests outside the org/workspace scope; tool-call audit log records every dispatch; gateway dashboard renders calls/denied/scopes; per-tool policy enforcement covered by tests. |
| **Phase 4 — Team workspace MVP** | Invite flow creates user, membership, role; review packet can be assigned and approved/denied by a different user; org budget cap blocks provider calls with a recorded `budget_exceeded` event; shared typed memory survives a workspace-rejoin. |
| **Phase 5 — Cloud-agent runtime loop** | At least two cloud-agent targets (Devin + Open SWE recommended) complete the runtime registration → task package → callback → proof ingestion loop in a fixture test; Mission Control lifecycle UI renders all states. |
| **Phase 6 — Enterprise control plane** | SSO/RBAC login flow works against a SAML/OIDC fixture; air-gapped install bundle builds; NATS JetStream durable queue replays an interrupted task-run idempotently; compliance report export covers SOC 2 + GDPR sample evidence. |

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Cloud features drag local-mode latency through shared code paths | Keep cloud-mode code behind `Runtime.mode` checks; benchmark local-mode startup and first-finding latency in CI; treat regressions as ship-blockers. |
| Telemetry redaction leaks repo content | Redaction is applied at event-envelope build time and tested with a corpus of secret/PII fixtures before any network egress; cloud doctor reports the redaction-policy version in use. |
| Migration from local SQLite to cloud Postgres loses proof/memory continuity | No automatic migration; `controlkeel cloud connect` records a forward-only workspace identity. Local proofs stay local; cloud-mode workspaces start fresh and reference local proofs by hash. |
| Hosted MCP becomes a single point of failure for team work | Local stdio MCP remains the default; hosted MCP is additive. Doctor command surfaces hosted MCP reachability so teams notice degradation. |
| Service-account tokens leak | Tokens are hashed at rest, rotated through `controlkeel service-accounts rotate`; hosted MCP rate-limits per token; cloud doctor flags tokens older than 90 days unused. |
| JetStream consumers process events non-idempotently | All cloud-mode events carry an idempotency key; consumers record processed keys in a TTL'd dedupe table; replay tests run in CI. |

## Relationship to local mode

Every phase preserves local mode as a first-class path. A solo builder on a laptop should never need to set up cloud infrastructure to use ControlKeel effectively. Cloud features are additive surfaces for teams that need them.

The local observability loop, deterministic validation, proof bundles, typed memory, benchmarks, and the full MCP skill surface all work without any cloud dependency. The cloud roadmap is about making those same surfaces useful across team boundaries, not about replacing them.

The key message remains: CK governs agent work wherever it runs. Cloud connectivity is how teams share that governance, not how individuals lose control of it.
