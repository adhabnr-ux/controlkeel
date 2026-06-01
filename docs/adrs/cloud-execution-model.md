# ADR: Cloud Execution Model — Hybrid (Local Agent + Cloud State)

**Date:** 2026-05-29
**Status:** Accepted
**Decision makers:** ControlKeel product + architecture review
**Closes:** CK-CLOUD-EXEC-003 (#293)

---

## Context

ControlKeel agents execute user-defined skills and hooks against local repositories. The cloud product needs to decide where execution happens:

1. **Hybrid** — agents stay on the user's IDE/device; governance state (findings, proofs, budget, policy) lives in the cloud; skills/hooks fire locally and emit results to cloud.
2. **Cloud sandbox** — ephemeral container per session clones the repo; skills/hooks run server-side on CK infrastructure.

This decision gates P3.4 and any future cloud-side execution feature.

## Decision

**We choose the hybrid model (Option 1).**

The codebase already implements this de facto:

- `Cloud.SyncEngine` handles workspace-scoped push/pull with dedup — the boundary between local execution and cloud governance state.
- `Cloud.Redactor` enforces per-schema `sync_fields/0` allowlists — only governance artifacts cross the boundary.
- `Accounts.authorize_cloud_execution/2` gates cloud-side operations at the workspace level.
- Skills are loaded from `.controlkeel/skills/*` on local disk — no cloud sync path exists for skill definitions or execution.
- The PubSub + LiveAuth hook pattern (P2/P2b) proves real-time cloud→agent notification works for membership eviction and sign-out-everywhere.

## Consequences

### Positive

- **Zero additional infrastructure cost** — no container orchestration (k8s, Firecracker, etc.).
- **Security** — user code never runs on CK infrastructure. Cloud only stores governance artifacts (findings, proofs, policy, budget telemetry).
- **Latency** — local execution is inherently faster than cloud round-trips for file I/O and shell operations.
- **Offline capable** — agents continue working without connectivity; sync when reconnected.
- **Extends naturally** — the existing sync engine already handles the data boundary. Future skill execution results just add a new sync payload type.

### Negative

- **No browser-only usage** — users must install a local agent (CLI or IDE extension). Zero-install browser sessions require Option 2.
- **Trust boundary on client** — the cloud cannot verify that skills executed correctly; it trusts the agent's reported findings and proofs. This is mitigated by signed payloads and audit trail.
- **Sync conflicts** — if the same workspace is active on multiple devices, governance state may conflict. Current sync engine uses last-write-wins per field; CRDTs are a future improvement.

## Deferred

The following are explicitly out of scope for the current product:

- **Cloud sandbox (Option 2)** — revisit if/when zero-install browser-only usage becomes a hard product requirement. Would require container orchestration, repo cloning, and sandboxed execution environments.
- **Skill sync** — skills are local-only by design. Cloud management of skill definitions is a P4+ feature.
- **Cross-device session handoff** — currently a single agent per workspace session. Multi-device sessions would require session state serialization.
- **CRDT-based sync** — last-write-wins is sufficient for current governance state. CRDTs would be needed for concurrent multi-device editing of the same policy.

## References

- `Cloud.SyncEngine` — lib/controlkeel/cloud/sync_engine.ex
- `Cloud.Redactor` — lib/controlkeel/cloud/redactor.ex
- `Accounts.authorize_cloud_execution/2` — lib/controlkeel/accounts.ex:1063
- `Cloud.RuntimeContext` — lib/controlkeel/cloud/runtime_context.ex
- CLOUD_READINESS.md — P3.4, finding CK-CLOUD-EXEC-003
