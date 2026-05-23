# Cloud / Team / Enterprise Roadmap

ControlKeel is **local-first by design**. Cloud and team features are strictly optional additions that preserve the local trust anchor. This document describes the roadmap for teams and organizations that need shared governance surfaces beyond a single laptop.

## North star

A portable governance plane that works the same way for a solo builder on a laptop and for a team of fifty agents across multiple runtimes — with cloud connectivity added only when the team explicitly opts in.

Local mode remains the default and the trust anchor. Cloud features layer on top, never replace it.

## Existing code-backed foundations

These surfaces already exist in the codebase and provide the structural scaffolding for cloud/team features:

| Surface | Code location | What it provides |
| --- | --- | --- |
| Runtime mode | `ControlKeel.Runtime` | `:local` / `:cloud` mode switch, bus selection, `cloud_repo_enabled?` |
| Cloud repo | `ControlKeel.CloudRepo` | Postgres adapter stub for cloud-mode persistence |
| Bus abstraction | `ControlKeel.Bus` + `Bus.Local` + `Bus.Nats` | Pluggable pub/sub: local ETS bus for single-node, NATS for distributed |
| Service accounts | `ControlKeel.Platform.ServiceAccount` | Named service accounts with hashed tokens and workspace scoping |
| OAuth scopes | `ControlKeel.ProtocolAccess` | Typed protocol scope model (`mcp:access`, `context:read`, `validate:run`, etc.) |
| Hosted MCP/A2A | `ControlKeel.ProtocolInterop` | Hosted MCP gateway, A2A agent-card discovery, scoped tool filtering |
| Platform APIs | `ControlKeel.Platform` | Task graphs, task runs, policy sets, webhooks, integration delivery |
| Telemetry handler | `ControlKeel.Analytics.TelemetryHandler` | Local telemetry event emission and persistence |
| Runtime config | `config/runtime.exs` | Cloud-mode config (Postgres, NATS, `DATABASE_URL`) |
| Local analytics | `ControlKeel.Analytics` | Local persistence of governance analytics |

These foundations are real shipped code, not aspirational stubs. They mean the cloud roadmap is about wiring existing surfaces together behind feature flags and opt-in controls, not about building from scratch.

## Trust and privacy model

| Principle | What it means in practice |
| --- | --- |
| **No telemetry by default** | ControlKeel does not phone home. All governance evidence stays local unless the operator explicitly enables sync. |
| **Opt-in telemetry levels** | Teams choose how much evidence leaves the local node. Levels are cumulative and strictly increasing. |
| **Local trust anchor** | Even with cloud sync enabled, the local database remains the primary source of truth. Cloud is a replica and coordination surface, not the authority. |
| **Service-account boundaries** | Remote access is scoped through named service accounts with fine-grained protocol scopes, not blanket admin keys. |
| **Evidence redaction** | Telemetry sync applies the same redaction rules as proof bundles and audit exports before data leaves the node. |

### Opt-in telemetry levels

| Level | What syncs | When to use |
| --- | --- | --- |
| **Health** | Heartbeat, version, workspace ID | Fleet monitoring; no governance content |
| **Governance metadata** | Finding counts, review status, budget summaries | Team dashboards; no source code or diffs |
| **Evidence sync** | Proof bundles, review packets, memory citations (redacted) | Cross-host coordination; shared audit trail |
| **Full enterprise audit** | Complete session transcripts (redacted), benchmark results, policy change history | Regulated environments; SOC 2 / GDPR compliance audit |

Level selection is per-workspace and requires explicit operator confirmation. There is no automatic escalation.

## Roadmap branches

### 1. Opt-in telemetry sync

Wire the existing local telemetry handler to an optional upstream sync endpoint. Governance evidence already emits structured events; the sync path serializes those events (with redaction) to a cloud endpoint when enabled.

**Dependencies**: telemetry level configuration UI, redaction pipeline, cloud endpoint auth.

### 2. Hosted MCP gateway

Extend the existing hosted MCP surface to serve as a team's single blessed entrypoint for agent tool access. Service accounts and OAuth scopes already exist; the gateway adds centralized routing, rate limiting, and per-team tool filtering.

**Dependencies**: multi-tenant workspace isolation, gateway routing config, per-team scope policies.

### 3. Team and multi-user approvals

Add multi-user approval flows so that review gates can require sign-off from specific team roles, not just the operator who started the session. The review/approval schema already supports human-in-the-loop decisions; this branch adds identity, roles, and delegation chains.

**Dependencies**: team identity model, role-based review routing, notification surfaces.

### 4. Organization budgets

Extend session and daily budgets to org-level rollups with per-team allocation, alerts, and circuit-breaker propagation. Budget controls already exist at the session level; this branch lifts them to the org hierarchy.

**Dependencies**: org/team hierarchy model, budget allocation API, alert routing.

### 5. Cloud-agent runtime loop

Enable agents to run against a shared cloud-hosted ControlKeel instance rather than requiring a local binary. The runtime export system already produces bundles for headless runtimes; this branch makes the CK instance itself the headless host.

**Dependencies**: cloud-mode persistence (CloudRepo), NATS bus for coordination, remote task dispatch.

### 6. JetStream coordination

Use NATS JetStream for durable event streaming between ControlKeel nodes, enabling multi-agent coordination, cross-host task dispatch, and replayable audit trails. The bus abstraction already supports NATS; JetStream adds persistence and replay.

**Dependencies**: NATS JetStream deployment, event schema versioning, consumer group management.

### 7. Enterprise self-host

Package ControlKeel for deployment behind enterprise firewalls with SSO integration, managed policy packs, and compliance reporting. The domain pack system already supports regulated verticals; this branch adds SSO, air-gapped deployment, and compliance export formats.

**Dependencies**: SAML/OIDC integration, air-gapped install artifacts, compliance report templates.

## Phased plan

### Phase 1: Narrowest cloud loop (upcoming)

The first cloud vertical slice is deliberately small: one team workspace, opt-in telemetry at the governance-metadata level, and a hosted MCP gateway for shared tool access.

- Workspace sync: health + governance metadata levels
- Hosted MCP gateway with service-account auth
- Team approval audit log

This phase does not include multi-user identity, org budgets, or cloud-agent runtimes. It proves the trust model, the sync pipeline, and the gateway pattern in production with the smallest possible blast radius.

### Phase 2: Team coordination

Build on the gateway to add multi-user review flows, team-scoped budgets, and shared memory/policy surfaces.

- Team identity and role-based review routing
- Per-team budget allocation with alerts
- Shared typed memory and policy sets across team members

### Phase 3: Distributed agents

Enable cloud-hosted agent execution with multi-node coordination.

- Cloud-agent runtime loop against shared CK instance
- NATS JetStream for durable event streaming
- Cross-host task dispatch and resume

### Phase 4: Enterprise compliance

Complete the enterprise surface with SSO, compliance reporting, and air-gapped deployment.

- SAML/OIDC SSO integration
- Compliance report exports (SOC 2, GDPR)
- Air-gapped install artifacts
- Managed policy packs for regulated verticals

## Relationship to local mode

Every phase preserves local mode as a first-class path. A solo builder on a laptop should never need to set up cloud infrastructure to use ControlKeel effectively. Cloud features are additive surfaces for teams that need them.

The local observability loop, deterministic validation, proof bundles, typed memory, benchmarks, and the full MCP skill surface all work without any cloud dependency. The cloud roadmap is about making those same surfaces useful across team boundaries, not about replacing them.
