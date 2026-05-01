# Omnara Integration Analysis for ControlKeel

## Executive Summary

After analyzing both Omnara and ControlKeel's architectures, **only 3-4 specific features from Omnara align with CK's governance/control-plane philosophy and should be considered for integration**. Most Omnara features (UI layers, mobile apps, voice, desktop apps, full daemon architecture) are out of scope for CK's mission.

## CK's Current Capabilities

### Workspace State Management
- **WorkspaceContext**: Captures git branch, head_sha, status_counts, instruction files, key files, orientation, design_drift
- **VirtualWorkspace**: Read-only file system operations (ls, read, find, grep) through a virtual workspace surface
- **Session model**: title, objective, risk_tier, status, budget, execution_brief, metadata
- **Task checkpoints**: checkpoint_type, summary, payload
- **Memory**: Typed memory with citations
- **Proof bundles**: Evidence of what worked/failed
- **Resume packets**: Session handoff state
- **Workspace snapshots**: Codebase state capture

### What CK Already Has That Omnara Doesn't
- Deterministic validation (FastPath, Semgrep)
- Policy packs and domain-specific governance
- Review gates and approval workflows
- Budget tracking and cost governance
- Agent routing and delegation
- Typed memory with citations
- Proof bundles and audit trails
- Benchmark evidence system

## Omnara Features Analysis

### ❌ NOT RELEVANT (Out of Scope for CK)

1. **Desktop/Mobile Apps** - UI layer, not governance
2. **Voice Interaction** - UX feature, not governance
3. **Full Daemon Architecture** - CK is an Elixir application with its own supervision tree
4. **Provider Authentication Flows** - CK assumes authentication is handled elsewhere
5. **Live Preview Tunnels** - This is a host/sandbox feature, not a control-plane feature
6. **Remote Sandboxing** - CK explicitly states it's the control plane, not the sandbox
7. **Web Dashboard** - CK has Mission Control web UI but doesn't need Omnara's dashboard approach

### ⚠️ PARTIALLY RELEVANT (Already Exists or Different Approach)

1. **Git Integration** - CK has git validation but not integrated commit/PR workflows
2. **Provider Abstraction** - CK has provider_broker.ex but not explicit provider management UI
3. **Session Management** - CK has sessions but not the same remote control model

### ✅ RELEVANT (Should Be Added)

## Recommended Integrations

### 1. Worktree-Aware Workspace Context

**What Omnara Has:**
- Explicit worktree concept for parallel work on different branches
- Workspace sync with checkpoint upload/restore for sandbox migration

**What CK Currently Has:**
- Git branch detection in WorkspaceContext
- Task checkpoints
- No explicit worktree management
- Checkpoints exist but no sync/restore workflow

**What to Add:**
- Extend `WorkspaceContext` to detect and track git worktrees
- Add worktree metadata to session binding
- Extend checkpoint system to support worktree-specific checkpoints
- Add `ck_worktree_list` and `ck_worktree_switch` MCP tools
- Update workspace resolution to be worktree-aware

**Implementation Approach:**
```elixir
# Extend lib/controlkeel/workspace_context.ex
defp detect_worktrees(repo_root) do
  # Use `git worktree list` to discover worktrees
  # Return list of worktree paths with branch info
end

# Extend session metadata
# Add "worktree_path" and "worktree_branch" to session.metadata
```

**Why This Aligns with CK:**
- Supports parallel development governance
- Fits CK's "bounded context" philosophy
- Enhances workspace state management without adding UI
- Local-only, no cloud dependency

---

### 2. Enhanced Checkpoint Sync/Restore

**What Omnara Has:**
- Workspace sync with checkpoint upload/restore
- Migration between local and sandbox environments
- Checkpoint-based state persistence

**What CK Currently Has:**
- Task checkpoints with checkpoint_type, summary, payload
- Resume packets
- Workspace snapshots
- No explicit sync/restore workflow

**What to Add:**
- Add `ck_checkpoint_create` and `ck_checkpoint_restore` MCP tools
- Extend checkpoint payload to include workspace state hash
- Add checkpoint export/import for workspace migration
- Integrate with existing resume packet system
- Add checkpoint validation before restore

**Implementation Approach:**
```elixir
# New module: lib/controlkeel/workspace_checkpoint.ex
defmodule ControlKeel.WorkspaceCheckpoint do
  def create(session_id, task_id, opts \\ []) do
    # Capture workspace state, git status, dependencies
    # Create checkpoint with hash
    # Store in task_checkpoints table
  end

  def restore(session_id, checkpoint_id) do
    # Validate checkpoint exists and belongs to session
    # Restore workspace state if possible
    # Update session metadata
  end

  def export(checkpoint_id) do
    # Export checkpoint as portable bundle
  end

  def_import(bundle) do
    # Import checkpoint bundle
  end
end
```

**Why This Aligns with CK:**
- Enhances resume packet capabilities
- Supports sandbox migration (a stated CK goal)
- Builds on existing checkpoint system
- No cloud dependency required

---

### 3. Git Workflow Integration

**What Omnara Has:**
- Web-based diff review
- Commit, push, PR creation from dashboard
- Git actions executed via relay

**What CK Currently Has:**
- Git validation via ck_validate
- Git status detection in WorkspaceContext
- No integrated git workflow commands
- Review system exists but not git-specific

**What to Add:**
- Add `ck_git_diff` MCP tool for governed diff review
- Add `ck_git_commit` with validation gate
- Add `ck_git_status` with finding integration
- Integrate git operations with review system
- Add git-specific findings (e.g., "commit message missing security context")

**Implementation Approach:**
```elixir
# New module: lib/controlkeel/git_workflow.ex
defmodule ControlKeel.GitWorkflow do
  def diff(project_root, base_ref, head_ref, opts \\ []) do
    # Generate diff
    # Run ck_validate on diff
    # Return diff with findings
  end

  def commit(project_root, message, opts \\ []) do
    # Validate commit message via ck_validate
    # Check for blocked findings
    # Execute commit if allowed
    # Record as task checkpoint
  end

  def status(project_root, opts \\ []) do
    # Get git status
    # Correlate with CK findings
    # Return status with governance context
  end
end
```

**Why This Aligns with CK:**
- Extends validation to git operations
- Integrates with existing review system
- No UI required (MCP tools only)
- Local-only, no cloud dependency

---

### 4. Remote Monitoring Hooks (Lightweight)

**What Omnara Has:**
- Full daemon architecture for remote control
- Mobile/web dashboard for monitoring
- Real-time event streaming

**What CK Currently Has:**
- Agent monitoring via Governance.AgentMonitor
- Session events via SessionEvent
- Observability reports
- Mission Control web UI
- No remote control API

**What to Add:**
- Add webhook/subscription system for session events
- Add `ck_monitor_subscribe` MCP tool for event streaming
- Extend SessionEvent to include remote-friendly payloads
- Add read-only monitoring API (no control, just visibility)
- Document monitoring integration points

**Implementation Approach:**
```elixir
# Extend lib/controlkeel/governance/agent_monitor.ex
def subscribe(session_id, subscriber_url, opts \\ []) do
  # Register webhook subscriber
  # Filter events based on opts
  # Send events as they occur
end

# Extend SessionEvent payload
# Add structured event types for remote consumption
```

**Why This Aligns with CK:**
- Extends observability without adding control
- Builds on existing monitoring system
- Read-only, maintains CK's governance model
- Optional feature, not core requirement

---

## Implementation Priority

### Phase 1 (High Value, Low Complexity)
1. **Worktree-aware workspace context** - Enhances existing WorkspaceContext, minimal new code
2. **Git workflow integration** - Adds MCP tools on top of existing validation

### Phase 2 (Medium Value, Medium Complexity)
3. **Enhanced checkpoint sync/restore** - Builds on existing checkpoint system, requires new module

### Phase 3 (Optional, Lower Priority)
4. **Remote monitoring hooks** - Nice to have but not core to CK's mission

---

## What NOT to Add (And Why)

### ❌ Live Preview Tunnels
- **Why:** This is a host/sandbox feature, not a control-plane feature
- **CK Philosophy:** CK is the harness, not the execution environment
- **Alternative:** Let hosts/sandboxes handle previews

### ❌ Full Daemon Architecture
- **Why:** CK is an Elixir application with its own supervision tree
- **CK Philosophy:** CK runs as needed, not as a background daemon
- **Alternative:** Use existing Elixir supervision tree

### ❌ Mobile/Web Dashboard
- **Why:** CK has Mission Control web UI for governance
- **CK Philosophy:** CK's UI is for governance, not remote control
- **Alternative:** Use existing Mission Control

### ❌ Voice Interaction
- **Why:** UX feature, not governance
- **CK Philosophy:** CK focuses on validation and review, not interaction modes
- **Alternative:** Let hosts handle voice

### ❌ Provider Authentication UI
- **Why:** CK assumes authentication is handled elsewhere
- **CK Philosophy:** CK is the control plane, not the auth provider
- **Alternative:** Use existing provider_broker.ex

---

## Summary

**Total Recommended Features: 3-4**
- Worktree-aware workspace context
- Enhanced checkpoint sync/restore
- Git workflow integration
- Remote monitoring hooks (optional)

**Total Rejected Features: 6-7**
- Desktop/mobile apps
- Voice interaction
- Full daemon architecture
- Live preview tunnels
- Remote sandboxes
- Web dashboard (already have Mission Control)
- Provider authentication UI

**Key Principle:** Only add features that enhance CK's governance/control-plane mission without turning CK into a host, sandbox, or UI platform.