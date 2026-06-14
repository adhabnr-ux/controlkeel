# Control Plane Architecture

ControlKeel is architected as the control plane for agent-led software delivery. It sits between coding agents (Claude, Codex, OpenCode, Cursor, etc.) and production, acting as a company brain to coordinate policy gates, findings, proofs, budgets, evals, and durable context.

## Core Stack
- **Phoenix + LiveView:** The core web and local UI layer.
- **Ecto + SQLite:** Embedded datastore for tracking findings, proofs, memory, budgets, and reviews.
- **Req:** For all outbound HTTP requests (proxying, cloud sync).
- **Burrito:** For single-binary distribution via GitHub releases.

## Major Subsystems
- **Agent Integration Layer (`AgentIntegration`, `AdapterRegistry`):** Adapts ControlKeel to 40+ native and headless runtimes (MCP, CLI plugins, Hooks).
- **Governance Engine (`Governance`, `FastPath`):** Evaluates diffs, plans, and arbitrary code through the deterministic scanner. Applied through PreToolUse hooks before mutations.
- **Protocol Router (`ControlKeelWeb.Router`):** Exposes MCP, A2A, and internal `/api/v1` routes with workspace-scoped authorization.
- **Typed Memory (`Memory`, `Memory.Store`):** Workspace/org-scoped, source-id idempotent, visibility-validated records with FTS + semantic retrieval.
- **Observability Cockpit:** Reconstructs agent sessions and provides human-gated regression loop mechanisms.
- **Cloud Sync (`Cloud.Sync`, `Cloud.SyncEngine`):** Dormant-until-configured bidirectional sync for findings, reviews, digests, and memory records. Token-authenticated, workspace-scoped, redacted before egress, idempotent by external_id.
- **Hook Enforcement:** PreToolUse hooks deny blocked shell/file operations; PostToolUse hooks nudge based on validation decisions; UserPromptSubmit hooks check blocked findings and budget pressure.

## Enforcement model
| Layer | Enforcement | Surface |
| --- | --- | --- |
| Scanner (FastPath) | Hard block via PreToolUse hook | Shell commands, sensitive file writes, secrets in prompts |
| Task completion gate | `{:error, :unresolved_findings}` | Mission.complete_task |
| Budget gate | `allowed: false` | Budget.estimate/commit |
| Review gate | Platform worker blocks execution | Platform.run_task |
| API workspace scope | 403 Forbidden | All /api/v1 object/action endpoints |
| Cloud sync scope | 403 Forbidden | CloudSyncController push/pull |

## Deployment Models
- **Local:** Runs as a CLI daemon on the developer's laptop (`controlkeel setup`). Single-user passthrough when unauthenticated.
- **Cloud/Self-Hosted:** Hosted control plane for distributed teams, accepting telemetry and proofs from local nodes. Service-account workspace scoping enforced on all API endpoints.
