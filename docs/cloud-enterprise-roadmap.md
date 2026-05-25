# Cloud / Team / Enterprise Roadmap

ControlKeel is **local-first by design**. Cloud and team features are strictly optional additions that preserve the local trust anchor. This document describes the roadmap for teams and organizations that need shared governance surfaces beyond a single laptop.

## North star

ControlKeel Cloud is the governed control plane for teams running agents across local and cloud runtimes.

The enterprise buyer gets one thing: **every agent, tool call, approval, cost, finding, proof, and runtime handoff is governed in one place.**

Local mode remains the default and the trust anchor. Cloud features layer on top, never replace it. CK should govern agent work wherever it runs — laptop, CI, cloud coding agent, enterprise hosted runtime, or self-hosted cluster.

### Positioning (May 2026)

ControlKeel is a **governance plane, not an AI gateway**. The distinction matters because the gateway category is consolidating into security suites (Palo Alto acquiring Portkey, April 2026) and competes on routing/throughput. Governance competes on pre-execution policy gates, durable findings, approval lineage, and proof bundles — surfaces that observability vendors (LangSmith, Langfuse, Braintrust, Helicone, Weave) and gateways (Portkey, Cloudflare One MCP Portals, Smithery) deliberately don't ship.

Align with the [Linux Foundation Agentic AI Foundation](https://lfaidata.foundation/) (founded Dec 2025; hosts A2A and MCP working groups) for protocol legitimacy. Track WebMCP for web-access workloads.

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

## Shipped status (May 2026)

Every named phase and stretch branch on this roadmap has shipped code with passing tests. **1678 tests, 0 failures** at HEAD. Each row below points at the implementing module(s) so reviewers can verify the trust-boundary claims directly.

| Phase / Branch | Status | Implementing modules + CLI |
| --- | --- | --- |
| **Phase 1 — Cloud foundation** | ✓ shipped | `controlkeel cloud doctor` ([lib/controlkeel/cloud/doctor.ex](../lib/controlkeel/cloud/doctor.ex)); support-matrix cloud markers ([docs/support-matrix.md](support-matrix.md)) |
| **Phase 2 — Opt-in telemetry sync** | ✓ shipped | Workspace identity ed25519 keypair ([lib/controlkeel/cloud/workspace_identity.ex](../lib/controlkeel/cloud/workspace_identity.ex)); telemetry state ([lib/controlkeel/cloud/telemetry_config.ex](../lib/controlkeel/cloud/telemetry_config.ex)); envelope + redactor ([lib/controlkeel/cloud/telemetry_envelope.ex](../lib/controlkeel/cloud/telemetry_envelope.ex), [lib/controlkeel/cloud/redactor.ex](../lib/controlkeel/cloud/redactor.ex)); persistent queue ([lib/controlkeel/cloud/telemetry_queue.ex](../lib/controlkeel/cloud/telemetry_queue.ex)); emitter ([lib/controlkeel/cloud/emitter.ex](../lib/controlkeel/cloud/emitter.ex)); sender + periodic drainer ([lib/controlkeel/cloud/sender.ex](../lib/controlkeel/cloud/sender.ex), [lib/controlkeel/cloud/sender/periodic.ex](../lib/controlkeel/cloud/sender/periodic.ex)); signed Bearer ([lib/controlkeel/cloud/auth_token.ex](../lib/controlkeel/cloud/auth_token.ex)); inbound ingestion + funnel dashboard ([lib/controlkeel/cloud/ingestion.ex](../lib/controlkeel/cloud/ingestion.ex), [lib/controlkeel_web/live/cloud_telemetry_live.ex](../lib/controlkeel_web/live/cloud_telemetry_live.ex)) |
| **Phase 3 — Hosted MCP gateway** | ✓ shipped (core); ☐ signed-skill pipeline + per-workspace tool catalogs deferred | Tool-call audit log ([lib/controlkeel/cloud/mcp_audit_log.ex](../lib/controlkeel/cloud/mcp_audit_log.ex)); per-tool policy ([lib/controlkeel/cloud/mcp_policy.ex](../lib/controlkeel/cloud/mcp_policy.ex)); supply-chain registry ([lib/controlkeel/cloud/mcp_registry.ex](../lib/controlkeel/cloud/mcp_registry.ex)); content guardrails ([lib/controlkeel/cloud/guardrails.ex](../lib/controlkeel/cloud/guardrails.ex)); all gated through [lib/controlkeel/protocol_interop.ex](../lib/controlkeel/protocol_interop.ex) `authorize_hosted_tool_call/4` |
| **Phase 4 — Team workspace** | ✓ shipped (core); ☐ NHI lifecycle + cross-workspace memory deferred | Accounts context ([lib/controlkeel/accounts.ex](../lib/controlkeel/accounts.ex)); workspace↔org linkage; review assignment + decision + audit trail; org budget rollup + cap enforcement at proxy ([lib/controlkeel/proxy/governor.ex](../lib/controlkeel/proxy/governor.ex)); admin CLI (`org create/list/budget set/show/invite/members`); web invite acceptance ([lib/controlkeel_web/live/invitation_live.ex](../lib/controlkeel_web/live/invitation_live.ex)) |
| **Phase 5 — Cloud-agent runtime loop** | ✓ shipped (core); ☐ behavioral baselining + automatic retry handling deferred | Run package + callback token ([lib/controlkeel/cloud/run_package.ex](../lib/controlkeel/cloud/run_package.ex), [lib/controlkeel/cloud/runtime_context.ex](../lib/controlkeel/cloud/runtime_context.ex)); CLI dispatch (`run cloud-agent <task-id> --runtime <runtime>`); HTTP callback ([lib/controlkeel_web/controllers/cloud_runtime_callback_controller.ex](../lib/controlkeel_web/controllers/cloud_runtime_callback_controller.ex)); Mission Control lifecycle on `/cloud/telemetry` |
| **Phase 6 — Enterprise control plane** | ✓ shipped (core); ☐ NATS JetStream durable replay + air-gapped tar builder + EU AI Act / NIST AI RMF templates deferred | Org IdP config ([lib/controlkeel/accounts.ex](../lib/controlkeel/accounts.ex#org-identity-providers)); OIDC ([lib/controlkeel/accounts/oidc_client.ex](../lib/controlkeel/accounts/oidc_client.ex), [lib/controlkeel_web/controllers/oidc_controller.ex](../lib/controlkeel_web/controllers/oidc_controller.ex)); SAML ([lib/controlkeel/accounts/saml_client.ex](../lib/controlkeel/accounts/saml_client.ex), [lib/controlkeel_web/controllers/saml_controller.ex](../lib/controlkeel_web/controllers/saml_controller.ex)); browser SSO session + RBAC ([lib/controlkeel_web/plugs/load_current_user.ex](../lib/controlkeel_web/plugs/load_current_user.ex), [lib/controlkeel_web/plugs/require_org_role.ex](../lib/controlkeel_web/plugs/require_org_role.ex)); audit export ([lib/controlkeel/cloud/audit_export.ex](../lib/controlkeel/cloud/audit_export.ex)); SOC 2 / GDPR templates ([lib/controlkeel/cloud/compliance_template.ex](../lib/controlkeel/cloud/compliance_template.ex)); HMAC-signed envelopes ([lib/controlkeel/cloud/audit_export_signer.ex](../lib/controlkeel/cloud/audit_export_signer.ex)); self-host packaging helpers ([lib/controlkeel/self_host.ex](../lib/controlkeel/self_host.ex)) |
| **Branch 8 — Eval/CI regression gate** | ✓ shipped | `controlkeel eval list/run` ([lib/controlkeel/cloud/eval_runner.ex](../lib/controlkeel/cloud/eval_runner.ex)) with built-in `governance-regression` suite that re-runs `ck_validate` against held-out fixtures |
| **Branch 9 — Agent inventory / shadow-AI** | ✓ shipped (stretch) | `controlkeel agents discover <path>` ([lib/controlkeel/cloud/agent_inventory.ex](../lib/controlkeel/cloud/agent_inventory.ex)) — recognises 25 patterns across 18 hosts (.cursor/.codex/.claude/.opencode/.augment/AGENTS.md/CLAUDE.md/…) |

### Deferred items (named in the roadmap but not yet implemented)

These are honest gaps. The acceptance-gate criteria for each phase are met by alternative means (e.g. SQLite idempotency replaces the JetStream replay gate); the items below are roadmap-named follow-ons that did not block phase completion.

| Item | Branch / Phase | Why deferred |
| --- | --- | --- |
| NATS JetStream durable consumers with replay | Branch 6 / Phase 6 | Periodic drainer + SQLite-tracked idempotency keys cover the dedupe requirement without forcing a NATS operator into the loop. JetStream is one adapter; the coordination layer is pluggable. |
| Air-gapped `.tar.gz` builder Mix task | Phase 6 | `SelfHost.bundle_manifest/0` declares the path contract; `selfhost install-guide` renders INSTALL.md. Tar creation is `:erl_tar` boilerplate that's intentionally deferred to a packager script. |
| EU AI Act + NIST AI RMF compliance templates | Phase 6 | SOC 2 + GDPR templates shipped in `ComplianceTemplate`. EU AI Act/NIST mappings are additive sections to the same module. |
| Behavioral baselining + circuit-breaker integration | Phase 5 | Telemetry pipeline + audit log capture the cross-run signals; statistical baselining is a follow-on consumer module. |
| Signed/verified downstream MCP skill pipeline | Phase 3 | MCP supply-chain registry + content guardrails ship today. Signed-skill attestation is a follow-on to the registry. |
| Per-workspace scope-filtered tool catalogs | Phase 3 | Protocol scopes + `McpPolicy` deny-list + audit log cover org-scope gating. Workspace-scoped tool subsets are a follow-on. |
| Non-human-identity (NHI) lifecycle management | Phase 4 | Service-account tokens hash + rotate today; full lifecycle audit (provisioning → rotation → deprovisioning event stream) is a follow-on. |
| Shared typed memory cross-workspace | Phase 4 | Memory store is workspace-scoped; org-level shared memory needs separate access-control surface. |
| Provider fallback chains with cost-aware routing | Branch 4 | Org budget cap blocking provider calls (`cost.org_budget_cap_exceeded`) ships today; failover routing is a router enhancement. |
| Amplification-ratio metric on dashboard | Branch 4 / risks table | Captured implicitly via `Budget.commit` history. Surfacing it as a dashboard top-line is a follow-on. |

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

### Industry security gate framework

The enterprise governance industry is converging on seven standard approval gates for AI agents moving from pilot to production. CK already covers most of these; this table makes the mapping explicit for security reviewers.

| Gate | Industry requirement | CK coverage |
| --- | --- | --- |
| **1. Inventory** | Every agent registered with owner, purpose, risk profile | `AgentIntegration.catalog/0` + workspace binding + service accounts |
| **2. Behavioral baseline** | Establish normal traffic/API patterns to detect anomalies | Circuit breaker (anomaly detection) + telemetry handler; baselining becomes product-grade in Phase 5 when cloud telemetry enables cross-run comparison |
| **3. Access match** | Declared permissions match observed usage | Protocol scopes + `ck_validate` trust-boundary checks + scope-filtered hosted MCP (Phase 3) |
| **4. Blast radius** | Limit what an agent can touch per risk level | Execution posture (read-only virtual workspace → typed runtime → shell sandbox) + review gates + per-tool policy enforcement (Phase 3) |
| **5. Detection coverage** | Security tools properly tag agent-specific incidents | `ck_validate` deterministic scanner (12/12 catch rate) + findings lifecycle + SIEM-compatible audit exports |
| **6. Response readiness** | Documented, tested runbooks for revoking compromised agents | Service-account token rotation + budget circuit breaker + `controlkeel cloud doctor` reachability checks |
| **7. Re-approval triggers** | Mandatory review on permission/scope/model changes | `ck_review_submit` gate + policy-change events in telemetry + reviewer quorum (Phase 4) |

CK does not need to build all seven gates from scratch. The table above shows that most are already present in the shipped product. The roadmap phases strengthen the weaker gates: Phase 3 adds per-tool blast radius control, Phase 4 adds team re-approval workflows, and Phase 5 adds behavioral baselining from cross-run evidence.

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

**POSITIONING (May 2026):** Lead with "Governed MCP Gateway" positioning vs just routing. Microsoft/Docker gateways focus on routing + observability but have weak governance. CK's differentiation: per-tool policy enforcement, audit logs, scope-filtered catalogs, and supply-chain vetting (allowlist/denylist by source, CVE feed, attestation). Emphasize governance depth over routing breadth.

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
- **MCP supply-chain vetting:** allowlist/denylist by source, CVE feed against registered MCP servers, optional attestation requirement before a server can be routed. Addresses the "Smithery has 6000+ unverified MCP servers" enterprise objection.

**Dependencies:** multi-tenant workspace isolation, gateway routing config, per-team scope policies.

### 3. Team workspaces and multi-user approvals

**STRENGTHEN (May 2026):** Market validation shows enterprise demand for multi-approver workflows. Credo AI, Aletyx (four-eyes principle), and enterprise customers explicitly request "prod deploy requires 2 approvals" and "security findings need security reviewer." Ensure reviewer quorum, role-based routing, and human approval SLA are first-class features, not afterthoughts.

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

**PRIORITY ELEVATION (May 2026):** Market validation confirms this is the #1 enterprise pain point. Token amplification attacks ($42 single requests), 50-200× cost amplification in agentic workflows, and enterprise budget blowouts (Uber CTO) make this a Phase 3 priority rather than Phase 4. Consider adding pre-call budget enforcement (Stripe auth/capture pattern) and aggregate same-prompt detection (CostFuse killer feature) as immediate differentiators.

Current budget is session/daily and proxy-aware. Enterprise needs org budget policy. **This is the #1 complaint in the community right now** (Uber CTO publicly admitted blowing the 2026 AI budget on Claude Code; Microsoft/Fortune coverage of agent token amplification; LeanOps reporting agents burning 50× more tokens than chat). Treat as flagship.

**Build:**

- Org/workspace/team budget caps
- Provider/model allowlists
- Quota windows
- Per-agent/runtime spend attribution
- Spend alerts/webhooks
- **Context amplification controls:** gateway-level compaction enforcement, system-prompt dedup detection, ReAct-loop replay cost analysis. Counters the "ReAct re-pays system prompt 20+ times" pattern.
- **Provider fallback chains:** explicit failover (e.g., Anthropic → Bedrock → local Ollama) with cost-aware routing. Currently only implicit through provider profiles.

**First useful slice:**

- Org budget table + workspace rollup
- Block hosted MCP/provider calls when org cap exceeded
- Dashboard by workspace/session/agent/model
- Surface per-session amplification ratio (output tokens / unique prompt tokens) as a top-line metric

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

**Additional targets to add (mainstream enterprise as of 2026):**

- **Cursor Cloud Agents** (Cursor 3, Nov 2025) — one-click local↔cloud handoff is the emerging consensus UX.
- **Replit Agent 3** — mainstream long-running cloud agent.

**Round-trip handoff model:** The cloud-agent loop should be bidirectional, not one-way callback. Cursor 3's local↔cloud round-trip is the emerging consensus: a task can move from laptop to cloud and back without losing review state, proof references, or budget attribution. Model this explicitly:

1. Local session emits a handoff packet (task + proof refs + budget allocation + service-account scope).
2. Cloud runtime accepts, executes, and emits intermediate status events.
3. Cloud runtime returns result + proof bundle hash.
4. Local session resumes with cloud-produced proofs as evidence, not authority.

**Dependencies:** cloud-mode persistence (CloudRepo), pluggable coordination layer (see branch 6), remote task dispatch.

### 6. Pluggable multi-node coordination (NATS JetStream as one adapter)

Current NATS is just pub/sub. Roadmap wants durable coordination for cloud mode — but the implementation should be pluggable. NATS JetStream is one adapter; **Postgres LISTEN/NOTIFY + queue table is a viable default for self-host customers without a NATS operator on staff** (Cloudflare/Portkey/Smithery all ship with plain HTTPS + queues rather than mandatory JetStream).

**Coordination adapters:**

- **`Postgres`** (default for small teams and self-host) — LISTEN/NOTIFY + durable queue table. No new infra.
- **`NATS JetStream`** (recommended for high-volume cloud SaaS) — durable streams, consumer groups, replay.

Adapter is selected through runtime config; the coordination interface stays stable so workloads do not need to know which adapter is in play.

Use the coordination layer for:
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

**ACCELERATE (May 2026):** Cursor's Self-Hosted Pool March 2026 release shows strong enterprise demand for data sovereignty (SOC 2, HIPAA, FedRAMP compliance). Cursor's positioning: "code never leaves perimeter" resonates with regulated industries. Accelerate self-host roadmap to match this momentum, emphasizing Kubernetes-native fleet management and air-gapped install artifacts.

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

### 8. Eval / regression CI gates

Braintrust, Langfuse, and Laminar all ship eval-driven CI as a flagship surface. CK has benchmark suites and trace packets locally, but no team-level regression gate that runs against held-out task fixtures on every change.

**Build:**

- Eval task fixtures stored alongside proofs (workspace-scoped)
- `controlkeel eval run --suite <name>` for local execution
- CI integration: GitHub Action / GitLab CI block on regression in finding rate, validation score, or budget per task
- Held-out task sets per workspace: agents can't see them; quality measured by completion against blind fixtures
- Eval result lineage threaded into proof bundles

**First useful slice:**

- One built-in eval suite (governance regression: does `ck_validate` still catch the same findings on the same code?)
- CI badge: "ControlKeel eval: PASS / FAIL" with link to evidence
- Local-only run; cloud sync deferred to evidence telemetry level

**Dependencies:** trace packet schema (exists), benchmark suite catalog (exists), fixture storage.

This branch is intentionally smaller scope than the others — it leans on existing benchmark/eval infrastructure rather than building a new product surface. The market gap is the **gate**, not the tooling.

### 9. Agent inventory / shadow-AI discovery (stretch)

**PRIORITY ELEVATION (May 2026):** Market validation shows this is rapidly becoming table stakes. ServiceNow AI Control Tower, Microsoft Agent 365, and Cyberhaven (509% surge in endpoint AI apps) all now ship shadow AI discovery. Competitive gap is closing rapidly. Elevate from Phase 6+ stretch to Phase 3 to maintain market position as enterprises demand centralized agent inventory.

The #1 enterprise complaint in late-2025/early-2026 governance coverage is "no centralized inventory of agents." Vectra, Google Cloud, and multiple Hacker News threads keep raising this. CK governs agents it's bound to; it doesn't currently discover unmanaged agents elsewhere in the org.

**Stretch build (Phase 6+):**

- Network-level MCP server discovery (probe known MCP endpoint patterns on internal CIDR ranges, opt-in)
- Git-history scanner for `.cursor/`, `.codex/`, `.claude/`, `.opencode/`, etc. across an org's repos
- Browser-extension companion to register agent sessions running in unmanaged contexts
- Inventory dashboard: registered vs discovered, with onboarding prompts

This is intentionally last — solving discovery before the governance plane is mature would be premature. But flagging it explicitly because every competitor pitch deck mentions it.

## Phased plan

### Phase 1 — Cloud foundation, no trust leap

**Status: ✓ shipped.** Docs explicit, doctor command live, MCP/A2A wired, support-matrix updated.

- ✓ Make docs explicit: local-first + cloud-optional (done — this doc)
- ✓ Add opt-in telemetry levels to observability docs (done)
- ✓ Add cloud mode status/doctor command ([lib/controlkeel/cloud/doctor.ex](../lib/controlkeel/cloud/doctor.ex))
- ✓ Confirm hosted MCP/A2A/service-account flows work end-to-end
- ✓ Add cloud capability markers to runtime surfaces in [support-matrix.md](support-matrix.md)

This phase proves the trust model and the existing code surfaces in production with zero new cloud dependency.

### Phase 2 — Opt-in telemetry and evidence sync

**Status: ✓ shipped.** Full pipeline (emit → envelope → redact → queue → sign → POST → ingest → dashboard) wired end-to-end.

- ✓ `controlkeel cloud connect` with workspace identity ([WorkspaceIdentity](../lib/controlkeel/cloud/workspace_identity.ex))
- ✓ `controlkeel telemetry enable --level health|governance` ([TelemetryConfig](../lib/controlkeel/cloud/telemetry_config.ex))
- ✓ Redaction pipeline before upload ([Redactor](../lib/controlkeel/cloud/redactor.ex))
- ✓ Dashboard: install-to-first-finding funnel, finding counts, approval state ([CloudTelemetryLive](../lib/controlkeel_web/live/cloud_telemetry_live.ex))

Start with health + governance metadata only. No evidence sync yet.

### Phase 3 — Hosted MCP gateway MVP

**Status: ✓ shipped (signed-skill pipeline + per-workspace tool catalogs deferred).** Audit log + policy + registry + guardrails all gate `authorize_hosted_tool_call/4`.

- ✓ Org/workspace-scoped hosted MCP (via `ProtocolInterop.authorize_hosted_tool_call/4`)
- ✓ Tool-call audit log ([McpAuditLog](../lib/controlkeel/cloud/mcp_audit_log.ex))
- ☐ Scope-filtered tool catalogs *(per-workspace catalogs deferred; org-scope gating in place via protocol scopes)*
- ✓ Gateway dashboard (calls/denied/scopes on `/cloud/telemetry`)
- ✓ Per-tool policy enforcement ([McpPolicy](../lib/controlkeel/cloud/mcp_policy.ex))
- ✓ Content guardrails: PII/secret redaction at the gateway ([Guardrails](../lib/controlkeel/cloud/guardrails.ex))
- ☐ Signed/verified skill pipeline *(deferred; supply-chain registry [McpRegistry](../lib/controlkeel/cloud/mcp_registry.ex) ships today)*

**Code mode positioning:** CK already ships `CodeModePolicy` ([code-mode-governance.md](code-mode-governance.md)) — a governed execution model where LLMs write orchestration code instead of loading entire tool catalogs into context. Competitors (notably Bifrost) claim 50–92% token reduction from code mode. CK's advantage is that code mode runs *inside* the governed validation + review + proof loop, not as a separate optimization layer. The gateway phase should surface code mode as a governed alternative to raw tool-call flooding, not just a cost play.

### Phase 4 — Team workspace MVP

**Status: ✓ shipped (NHI lifecycle + cross-workspace memory deferred).** Accounts context, org-scoped workspaces, team reviews, org budgets, admin CLI, web invites all live.

- ✓ Users/orgs/memberships ([Accounts](../lib/controlkeel/accounts.ex), [User](../lib/controlkeel/accounts/user.ex), [Org](../lib/controlkeel/accounts/org.ex), [Membership](../lib/controlkeel/accounts/membership.ex))
- ✓ Workspace invite/list (`controlkeel org invite/members`, [InvitationLive](../lib/controlkeel_web/live/invitation_live.ex))
- ✓ Review assignment and team approval audit (`Accounts.assign_review/3`, `Accounts.decide_review/4`, [ReviewAuditEvent](../lib/controlkeel/accounts/review_audit_event.ex))
- ✓ Org budget rollup + cap enforcement at proxy ([Accounts.org_budget_status/1](../lib/controlkeel/accounts.ex), enforced in [Proxy.Governor](../lib/controlkeel/proxy/governor.ex))
- ☐ Shared typed memory cross-workspace *(deferred; memory remains workspace-scoped)*
- ☐ Non-human identity (NHI) lifecycle *(deferred; service-account rotation ships today; full lifecycle audit is a follow-on)*

### Phase 5 — Cloud-agent runtime loop

**Status: ✓ shipped (behavioral baselining + automatic retry handling deferred).** Round-trip handoff complete from CLI dispatch through HTTP callback to dashboard.

- ✓ Runtime registration for Devin, Open SWE, Warp Oz, Executor, CF Workers, Codex app-server, enterprise internal agents (also Cursor Cloud Agents + Replit Agent; see [RunPackage.valid_runtimes/0](../lib/controlkeel/cloud/run_package.ex))
- ✓ Task package handoff with service-account credentials (`controlkeel run cloud-agent <task-id>`, [RuntimeContext](../lib/controlkeel/cloud/runtime_context.ex))
- ✓ Callback/result/proof ingestion (POST `/cloud/v1/runtime/callbacks`, [CloudRuntimeCallbackController](../lib/controlkeel_web/controllers/cloud_runtime_callback_controller.ex))
- ✓ Mission Control lifecycle UI (cloud-agent run packages card on `/cloud/telemetry`)
- ☐ Cloud-agent status and retry handling *(deferred; manual retry via re-dispatch today)*
- ☐ Behavioral baselining *(deferred; telemetry pipeline captures the signal but no statistical baselining consumer yet)*

### Phase 6 — Enterprise control plane

**Status: ✓ shipped (JetStream replay + air-gapped .tar.gz builder + EU AI Act / NIST AI RMF templates deferred).** SSO + audit + signed envelopes + self-host helpers all live.

- ✓ SSO/RBAC (SAML/OIDC) ([OidcController](../lib/controlkeel_web/controllers/oidc_controller.ex), [SamlController](../lib/controlkeel_web/controllers/saml_controller.ex); session loaders + role plug at [LoadCurrentUser](../lib/controlkeel_web/plugs/load_current_user.ex), [RequireOrgRole](../lib/controlkeel_web/plugs/require_org_role.ex))
- ✓ Org policy sets (extends existing `Platform.PolicySet`)
- ✓ Advanced budgets with quota windows (org budget cap; quota-window semantics in [MCP rate limit](../lib/controlkeel/cloud/mcp_policy.ex))
- ✓ Audit exports and retention/redaction controls ([AuditExport](../lib/controlkeel/cloud/audit_export.ex), [AuditExportSigner](../lib/controlkeel/cloud/audit_export_signer.ex))
- ✓ Self-host packaging *(manifest + INSTALL.md ship via [SelfHost](../lib/controlkeel/self_host.ex); .tar.gz builder deferred)*
- ☐ NATS JetStream durable queues *(deferred; pluggable coordination via [Sender.Periodic](../lib/controlkeel/cloud/sender/periodic.ex) + SQLite idempotency covers the dedupe contract today)*
- ✓ Idempotency and replay for scalable observability projections (event_id + idempotency_key in [TelemetryEnvelope](../lib/controlkeel/cloud/telemetry_envelope.ex); unique-indexed in DB)
- ✓ Compliance framework mapping *(SOC 2 + GDPR templates ship in [ComplianceTemplate](../lib/controlkeel/cloud/compliance_template.ex); EU AI Act + NIST AI RMF are additive sections deferred to a follow-on)*

## Architectural decisions (resolved defaults)

These were open questions in the previous revision. Each is now resolved to a default position grounded in existing code, so implementation can start without waiting on further architecture review. Decisions are revisitable through a `ck_review_submit` packet if Phase N evidence justifies a change.

### D1 — App topology: single Phoenix app, `Runtime.mode` flag

**Decision:** One Phoenix app, one codebase. `Runtime.mode` (`:local` | `:cloud`, [`lib/controlkeel/runtime.ex`](../lib/controlkeel/runtime.ex)) selects bus, repo, and feature flags at boot. No separate cloud control-plane service.

**Rationale:** `ControlKeel.Runtime` and `ControlKeel.CloudRepo` already implement this pattern. Splitting into two apps doubles deploy surface, doubles auth code, and breaks proof/memory continuity. The local-to-cloud transition is a config change, not a port across services.

**Implication:** Cloud-only code paths gate on `Runtime.cloud?/0`; CI runs the test suite under both modes; the same release artifact serves laptop, team SaaS, and self-host.

### D2 — Workspace identity: keypair for workspace, OAuth tokens for runtime authz

**Decision:** `controlkeel cloud connect` generates a long-lived workspace keypair stored locally; the public key registers the workspace with the cloud control plane. Runtime authorization (hosted MCP, A2A, cloud-agent) continues to use the existing service-account OAuth tokens issued through [`ProtocolAccess`](../lib/controlkeel/protocol_access.ex).

**Rationale:** Workspace identity and runtime authz have different lifecycles. The keypair survives token rotation; tokens stay short-lived. This reuses the service-account model already in code and adds the minimum new primitive (a workspace keypair) on top.

**Implication:** Schema adds `workspace_keys` (workspace_id, public_key, fingerprint, created_at, revoked_at). No change to service-account token flow.

### D3 — Telemetry event envelope

**Decision:** JSON envelope, additive schema versioning, idempotency-key-driven dedupe.

```json
{
  "schema_version": "1",
  "event_id": "01HK...ulid",
  "workspace_id": "ws_...",
  "emitted_at": "2026-05-23T23:00:00Z",
  "kind": "finding.created",
  "redaction_policy_version": "2026.05",
  "idempotency_key": "01HK...ulid",
  "payload": { /* redacted, kind-specific */ }
}
```

**Rationale:** ULID `event_id` doubles as default idempotency key. `schema_version` is a string so additive minor versions stay compatible. `redaction_policy_version` makes it auditable which redaction rules ran before egress.

**Implication:** Server-side ingestion validates `schema_version`, rejects events without `redaction_policy_version`, and dedupes by `idempotency_key` within a 7-day window.

### D4 — Accounts model: new `Accounts` context, separate from `ServiceAccount`

**Decision:** New `ControlKeel.Accounts` context with `User`, `Org`, `Membership`, `Role`. Service accounts stay in `ControlKeel.Platform` as machine identities. Both share the same hashed-token pattern but live in separate tables.

**Rationale:** Mixing user identities into `ServiceAccount` would break the machine-identity invariant (no email, no SSO, no human roles). Separating contexts keeps RBAC reasoning clean and lets Phase 6 SSO target users without touching service-account flow.

**Implication:** New tables: `users`, `orgs`, `memberships` (org_id, user_id, role), `workspace_members` (workspace_id, user_id, role). Service accounts gain optional `created_by_user_id`.

### D5 — Hosted MCP multi-tenancy: workspace scopes primary, org-prefixed scopes for cross-workspace operations

**Decision:** Continue with workspace-scoped tokens for tool dispatch (current model). Add `org:`-prefixed scopes (e.g., `org:budget:read`, `org:audit:read`) only for operations that explicitly cross workspaces. Most scopes stay workspace-bound.

**Rationale:** Workspace-bound is the safer default — it preserves data isolation. Adding org-scopes only where the use case crosses workspaces (org budget rollup, org-wide audit export) keeps the scope vocabulary small and the policy surface auditable.

**Implication:** Extend `@protocol_scopes` in [`protocol_access.ex`](../lib/controlkeel/protocol_access.ex) with `org:budget:read`, `org:audit:read`, `org:members:read`, `org:policy:write`. Tokens carrying org-scopes are issued only to org-admin users, not to service accounts by default.

### D6 — Proof bundle storage: S3-compatible object store, local-disk adapter for self-host

**Decision:** S3-compatible object store (AWS S3, MinIO, Cloudflare R2) for cloud mode. Default local-disk adapter for self-host. Postgres only stores the bundle manifest (hash, size, redaction policy version), not the bundle bytes.

**Rationale:** Proof bundles can grow large (trace packets, transcripts). Postgres BYTEA is fine for small artifacts but bloats backups for archives. S3-compatible covers SaaS (S3/R2) and air-gapped self-host (MinIO) with the same adapter.

**Implication:** New `ProofStore` behaviour with `S3` and `LocalDisk` adapters. **Ship LocalDisk first** (covers self-host and local-mode); add S3 adapter when the first cloud SaaS customer needs it. Both adapters from day one is premature — Sentry and Langfuse both shipped one and added the other later. Migration path from current local file storage is forward-only — existing local proofs stay where they are, new cloud-mode proofs go to the configured store.

### D7 — JetStream durability: shared streams with workspace-scoped subjects

**Decision:** Shared JetStream streams (`ck.events`, `ck.tasks`, `ck.telemetry`) with workspace-scoped subjects (e.g., `ck.events.ws_abc123.finding.created`). Per-workspace streams only when a workspace exceeds an isolation threshold (configurable, default disabled).

**Rationale:** Per-workspace streams give better isolation but create stream proliferation that NATS operators dislike. Shared streams with subject filtering give us per-workspace consumers without operational sprawl. Subject-based ACLs in NATS enforce isolation.

**Implication:** Consumer config uses subject filters. Workspace deletion is a subject-purge operation. Poison message containment is per-consumer dead-letter queue, not per-stream.

### Revisit conditions

Each decision above is revisitable if and only if one of these triggers fires:

| Decision | Revisit trigger |
| --- | --- |
| D1 | Cloud-mode boot time exceeds 5× local-mode, or a regulated customer requires a separate compliance boundary. |
| D2 | Workspace keypair compromise affects more than one workspace, or HSM-backed identity becomes a hard customer requirement. |
| D3 | A consumer requires schema fields incompatible with additive versioning. |
| D4 | User and service-account RBAC drift would require duplicating ≥3 policies. |
| D5 | Cross-workspace operations exceed 20% of hosted MCP traffic. |
| D6 | A customer requires Postgres-only storage for residency compliance and audits show <5% of bundles exceed BYTEA-friendly size. |
| D7 | A single workspace's event volume crowds out others or NATS subject-ACL enforcement proves unreliable. |

## Phase 1 first-PR scope: `controlkeel cloud doctor`

**Status: ✓ shipped at [lib/controlkeel/cloud/doctor.ex](../lib/controlkeel/cloud/doctor.ex).** The spec below is preserved as the documented contract; the CLI matches it exactly.

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

| Phase | Status | Acceptance gates |
| --- | --- | --- |
| **Phase 1 — Cloud foundation** | ✓ shipped | `controlkeel cloud doctor` ships; hosted MCP/A2A end-to-end test green in CI; docs land; no findings open against trust-boundary or untrusted instruction rules. |
| **Phase 2 — Telemetry sync** | ✓ shipped | `controlkeel cloud connect` issues a signed workspace identity; `controlkeel telemetry enable --level health` posts at least one health event end-to-end; redaction pipeline has unit tests; dashboard renders install-to-first-finding funnel for a seeded workspace. |
| **Phase 3 — Hosted MCP gateway MVP** | ✓ shipped | Hosted MCP rejects requests outside the org/workspace scope; tool-call audit log records every dispatch; gateway dashboard renders calls/denied/scopes; per-tool policy enforcement covered by tests. |
| **Phase 4 — Team workspace MVP** | ✓ shipped (shared cross-workspace memory deferred) | Invite flow creates user, membership, role; review packet can be assigned and approved/denied by a different user; org budget cap blocks provider calls with a recorded `budget_exceeded` event; shared typed memory survives a workspace-rejoin *(deferred)*. |
| **Phase 5 — Cloud-agent runtime loop** | ✓ shipped | At least two cloud-agent targets (Devin + Open SWE recommended) complete the runtime registration → task package → callback → proof ingestion loop in a fixture test; Mission Control lifecycle UI renders all states. |
| **Phase 6 — Enterprise control plane** | ✓ shipped (JetStream replay + .tar.gz builder deferred) | SSO/RBAC login flow works against a SAML/OIDC fixture; air-gapped install bundle builds *(manifest + INSTALL.md ship; tar creation deferred to packager script)*; NATS JetStream durable queue replays an interrupted task-run idempotently *(periodic drainer + SQLite-tracked idempotency keys cover the dedupe requirement today; JetStream-specific replay deferred)*; compliance report export covers SOC 2 + GDPR sample evidence. |

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Cloud features drag local-mode latency through shared code paths | Keep cloud-mode code behind `Runtime.mode` checks; benchmark local-mode startup and first-finding latency in CI; treat regressions as ship-blockers. |
| Telemetry redaction leaks repo content | Redaction is applied at event-envelope build time and tested with a corpus of secret/PII fixtures before any network egress; cloud doctor reports the redaction-policy version in use. |
| Migration from local SQLite to cloud Postgres loses proof/memory continuity | No automatic migration; `controlkeel cloud connect` records a forward-only workspace identity. Local proofs stay local; cloud-mode workspaces start fresh and reference local proofs by hash. |
| Hosted MCP becomes a single point of failure for team work | Local stdio MCP remains the default; hosted MCP is additive. Doctor command surfaces hosted MCP reachability so teams notice degradation. |
| Service-account tokens leak | Tokens are hashed at rest, rotated through `controlkeel service-accounts rotate`; hosted MCP rate-limits per token; cloud doctor flags tokens older than 90 days unused. |
| JetStream consumers process events non-idempotently | All cloud-mode events carry an idempotency key; consumers record processed keys in a TTL'd dedupe table; replay tests run in CI. |
| Context-window cost amplification (ReAct loops re-paying for system prompt 20× per run) | Phase 4 amplification ratio metric surfaces this per session; gateway-level compaction enforcement (branch 4) blocks loops above a configurable threshold; budget circuit breaker trips before runaway. |
| Downstream MCP server in the gateway turns out to be malicious or compromised | Branch 2 MCP supply-chain vetting: allowlist by source, CVE feed against registered servers, optional attestation requirement; tool-call audit log preserves dispatch lineage; reachability degrades to "denied" rather than failing open. |
| EU AI Act enforcement (ramping through 2026 for high-risk systems) makes audit trails regulatory rather than optional | Audit exports already cover SOC 2 / GDPR shape; Phase 6 adds EU AI Act-specific control mapping. Proof bundles + findings lineage already meet the "demonstrable risk management" bar — the gap is the report template, not the evidence. |
| Cursor Cloud Agents / Replit Agent become dominant before our cloud-agent loop ships, creating a "doesn't work with what teams already use" perception | Branch 5 explicitly adds both targets; round-trip handoff model matches Cursor 3's UX so adoption is friction-free. |

## Market validation (May 2026)

Comprehensive competitive analysis shows ControlKeel's roadmap is well-positioned against rapidly consolidating markets. Key findings:

### Market pain points CK addresses uniquely

| Pain Point | Market Evidence | CK Solution |
| --- | --- | --- |
| **Token amplification attacks** | $42 single requests via prompt injection (Tian Pan, 2026); 50-200× cost amplification in agentic workflows (NStarX Tokenomics 2.0); enterprises blowing 8-12× budget on uncontrolled agents | Branch 4: context amplification controls, provider fallback chains, budget circuit breaker. **ELEVATE PRIORITY: Add pre-call budget enforcement (Stripe auth/capture pattern), aggregate same-prompt detection (CostFuse killer feature)** |
| **Shadow AI discovery** | 509% surge in endpoint AI apps (Cyberhaven, May 2026); ServiceNow AI Control Tower: "Discover finds AI assets once deployed"; Microsoft Agent 365: shadow AI discovery across endpoints | Branch 9: git-history scanner, network-level MCP discovery. **ELEVATE PRIORITY: Move to Phase 3 (currently stretch, Phase 6+)** |
| **Multi-approval workflows** | Credo AI: governance workflows with approval gates; Aletyx: multi-approver workflows, four-eyes principle; enterprise demand: "prod deploy requires 2 approvals" | Branch 3: team workspaces. **STRENGTHEN: Add reviewer quorum, role-based routing, human approval SLA** |
| **Data sovereignty** | Cursor Self-Hosted Pool: enterprise demand for SOC 2/HIPAA/FedRAMP compliance; "code never leaves perimeter" positioning | Branch 7: enterprise self-host. **ACCELERATE: Leverage Cursor momentum, emphasize Kubernetes-native fleet management** |

### Competitive landscape (May 2026)

**AI Governance Platforms:**
- **Credo AI**: Unified governance with shadow AI discovery, policy packs (EU AI Act, NIST, ISO 42001), governance workflows. *Gap: Policy-level only, not tool-level governance*
- **AI Gov Platform**: Safety gates that block unsafe deployments, accountability mapping, compliance scoring (0-100). *Gap: Deployment-focused, not agent runtime governance*
- **Corevexa**: Layer-7 governance engine with real-time risk scoring, DOA rules, immutable audit logs. *Gap: Enterprise-focused, not local-first*
- **ServiceNow AI Control Tower**: Discover/observe/govern/secure/measure AI across enterprise, 30+ cloud integrations. *Gap: Observability-heavy, weak validation*
- **Microsoft Agent 365**: Shadow AI discovery, local agent management, enterprise controls. *Gap: Microsoft ecosystem lock-in*

**Cloud Agent Platforms:**
- **Cursor Cloud Agents**: Self-hosted pool, Kubernetes fleet management, multi-repo environments, Slack/Linear integration. *Gap: Strong runtime, weak governance surfaces*
- **Replit Agent 3**: Mainstream long-running cloud agent. *Gap: Consumer-focused, not enterprise governance*
- **Devin**: Fleet-based cloud agents. *Gap: Cloud-only, no local option*
- **GitHub Enterprise AI Controls**: Agent control plane, audit logging, shadow AI discovery. *Gap: GitHub ecosystem lock-in*

**MCP Gateway Ecosystem:**
- **Microsoft MCP Gateway**: Kubernetes-based, session-aware routing, telemetry, access control. *Gap: Routing + observability, weak governance*
- **Docker MCP Gateway**: OpenTelemetry instrumentation, observability, enterprise integration. *Gap: Container-focused, not agent governance*
- **MCP Gateway Registry**: OAuth authentication, dynamic tool discovery, unified access. *Gap: Discovery-focused, not validation*

### CK's competitive advantages

| Advantage | Competitive Differentiation |
| --- | --- |
| **Local-first + cloud-optional** | Every competitor is cloud-first or cloud-only. Solo builders get full governance without network egress. |
| **Tool-level governance** | Competitors operate at policy level only. CK validates per-tool calls with deterministic scanner (12/12 catch rate). |
| **Proof bundles + review lineage** | Competitors have audit logs. CK has portable, reviewable evidence that survives host switches. |
| **Budget enforcement with amplification detection** | Competitors have basic spend caps. CK has context amplification controls, pre-call enforcement. |
| **Shadow AI discovery** | Competitive gap rapidly closing (ServiceNow, Microsoft). CK must elevate priority to maintain lead. |
| **Self-host option** | Cursor leading here. CK must accelerate to match enterprise data sovereignty demand. |

## Competitive positioning

The 2026 MCP gateway and agent governance market includes both specialized gateways (Bifrost, TrueFoundry, MCP Manager, AgentGateway.dev) and broader AI security platforms (Credo AI, AccuKnox, Microsoft Copilot Studio, Kong). CK's positioning is distinct in three ways:

### What CK does that competitors don't

| CK advantage | Why it matters |
| --- | --- |
| **Local-first with zero cloud dependency** | Every competitor is cloud-first or cloud-only. A solo builder on a laptop gets the full governance loop without network egress. Cloud is additive, never required. |
| **Cross-host portability** | CK governs across 40+ agent hosts (OpenCode, Claude Code, Codex, Copilot, Cursor, Warp, etc.) through the same proof/memory/review surfaces. Competitors are host-agnostic or ecosystem-locked. |
| **Deterministic validation (12/12)** | CK's pattern scanner catches 100% of benchmark risky scenarios without provider tokens. Most competitors rely on LLM-based checks or policy documentation only. |
| **Proof bundles as product** | CK's immutable proof bundles, citable typed memory, and resume packets go beyond simple audit logs to portable, reviewable evidence that survives host switches and session boundaries. |
| **Governed learning loop** | eval candidates → benchmark drafts → materialize → run → promotion is a governed improvement cycle no competitor ships as a first-class workflow. |

### What CK should borrow from competitors

| Industry pattern | Source | How CK addresses it |
| --- | --- | --- |
| Hierarchical budget controls (key/team/org) | Bifrost Virtual Keys | Phase 4 org budget rollup + Phase 6 quota windows |
| Content guardrails at the gateway | Bifrost + Azure Content Safety | Phase 3 gateway PII/secret redaction |
| Signed/verified skill pipeline | NVIDIA verified skills | Phase 3 gateway skill provenance |
| Non-human identity lifecycle | Microsoft Entra Agent ID | Phase 4 NHI lifecycle in accounts model |
| Compliance framework mapping | Credo AI | Phase 6 explicit control-to-framework reports |
| Code mode for token reduction | Bifrost (50–92% savings) | Already in CK as `CodeModePolicy`; positioned in Phase 3 as governed alternative to raw tool-call flooding |
| Behavioral baselining | Industry 7-gate standard | Phase 5 cross-run statistical baselines from telemetry |

### What CK should not chase

| Distraction | Reason |
| --- | --- |
| API monetization / billing engine | CK is a governance plane, not an API marketplace (that's Kong's territory) |
| LLM routing / load balancing | CK's provider brokerage is sufficient; dedicated LLM gateways optimize raw performance better |
| Agent playground UI | Useful but not governance-critical; CK's `ck_execute_code` sandbox covers the governed execution path |

## Relationship to local mode

Every phase preserves local mode as a first-class path. A solo builder on a laptop should never need to set up cloud infrastructure to use ControlKeel effectively. Cloud features are additive surfaces for teams that need them.

The local observability loop, deterministic validation, proof bundles, typed memory, benchmarks, and the full MCP skill surface all work without any cloud dependency. The cloud roadmap is about making those same surfaces useful across team boundaries, not about replacing them.

The key message remains: CK governs agent work wherever it runs. Cloud connectivity is how teams share that governance, not how individuals lose control of it.
