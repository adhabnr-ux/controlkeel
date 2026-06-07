# Control Plane Architecture

ControlKeel is architected as the control plane for agent-led software delivery. It sits between coding agents (Claude, Codex, OpenCode, Cursor, etc.) and production, acting as a company brain to coordinate policy gates, findings, proofs, budgets, evals, and durable context.

## Core Stack
- **Phoenix + LiveView:** The core web and local UI layer.
- **Ecto + SQLite:** Embedded datastore for tracking findings, proofs, memory, budgets, and reviews.
- **Req:** For all outbound HTTP requests (proxying, cloud sync).
- **Burrito:** For single-binary distribution via GitHub releases.

## Major Subsystems
- **Agent Integration Layer (`AgentIntegration`, `AdapterRegistry`):** Adapts ControlKeel to 40+ native and headless runtimes (MCP, CLI plugins, Hooks).
- **Governance Engine (`Governance`, `Policy`):** Evaluates diffs, plans, and arbitrary code through the deterministic scanner.
- **Protocol Router (`ControlKeelWeb.Router`):** Exposes MCP, A2A, and internal `/api/v1` routes.
- **Observability Cockpit:** Reconstructs agent sessions and provides human-gated regression loop mechanisms.
- **Sync Engine:** (Optional) pushes local telemetry and proofs to the cloud workspace for team visibility.

## Deployment Models
- **Local:** Runs as a CLI daemon on the developer's laptop (`controlkeel setup`).
- **Cloud/Self-Hosted:** Hosted control plane for distributed teams, accepting telemetry and proofs from local nodes.
