# Omnara Integration Opportunities

## Overview

ControlKeel and Omnara serve complementary purposes:
- **ControlKeel**: Governance, validation, and evidence layer for agent work
- **Omnara**: Remote control, session management, and cross-device coordination

## Integration Strategy

### 1. CK as an Omnara Provider Extension

**Concept**: Package CK's governance capabilities as an optional Omnara provider extension.

**Implementation**:
```elixir
# Omnara provider configuration
{
  "name": "controlkeel-governance",
  "type": "governance_provider",
  "capabilities": [
    "validation",
    "findings",
    "review_gates",
    "checkpoint_management",
    "git_workflow"
  ],
  "mcp_server": "io.github.aryaminus/controlkeel",
  "installation": "brew install aryaminus/controlkeel"
}
```

**Benefits**:
- Omnara users get CK governance without switching tools
- Omnara's remote control + CK's governance = comprehensive solution
- Omnara's daemon can trigger CK validation before destructive operations

### 2. Checkpoint Interoperability

**Concept**: Make CK checkpoints compatible with Omnara's workspace sync system.

**Implementation**:
- Extend `WorkspaceCheckpoint.export/1` to output Omnara-compatible format
- Add Omnara workspace state to CK checkpoint payload
- Support bidirectional checkpoint conversion

**Benefits**:
- Users can migrate between Omnara sandbox and CK-governed local sessions
- Omnara's cloud sync + CK's governance = best of both worlds
- Consistent state management across both systems

### 3. Git Workflow Integration

**Concept**: Integrate CK's governed git operations with Omnara's git integration dashboard.

**Implementation**:
- Add CK validation results to Omnara's git diff view
- Show CK findings alongside Omnara's PR review UI
- Use CK's `ck_git_commit` validation in Omnara's commit flow

**Benefits**:
- Omnara users get CK security validation in their git workflow
- Omnara's UI + CK's validation = more secure shipping
- Consistent governance across both systems

### 4. Remote Monitoring via Omnara

**Concept**: Use Omnara's remote control infrastructure as a transport for CK's monitoring hooks.

**Implementation**:
- CK's `RemoteMonitoring.publish_event/3` can push to Omnara's event stream
- Omnara's mobile/web apps can display CK findings and review status
- Omnara's daemon can act as a CK event subscriber

**Benefits**:
- CK governance visibility on mobile/web through Omnara
- Omnara's existing infrastructure vs building new CK monitoring UI
- Leverage Omnara's authentication and user management

### 5. Worktree Management Integration

**Concept**: Integrate CK's worktree awareness with Omnara's workspace/worktree model.

**Implementation**:
- Map Omnara worktrees to CK worktree metadata
- Synchronize worktree state between both systems
- Use CK's worktree validation in Omnara's worktree switching

**Benefits**:
- Consistent worktree management across both systems
- Omnara's worktree UI + CK's governance = safer parallel development
- Single source of truth for worktree state

## Recommended Integration Priority

### Phase 1: High Value, Low Complexity
1. **CK as Omnara Provider Extension** - Package CK MCP server as Omnara provider
2. **Git Workflow Integration** - Add CK validation to Omnara's git operations

### Phase 2: Medium Value, Medium Complexity  
3. **Checkpoint Interoperability** - Enable state migration between systems
4. **Worktree Management Integration** - Synchronize worktree awareness

### Phase 3: Optional, Lower Priority
5. **Remote Monitoring via Omnara** - Use Omnara infrastructure for CK monitoring

## Implementation Example: Omnara Provider Extension

```yaml
# omnara-providers/controlkeel.yaml
name: controlkeel-governance
version: 1.0.0
description: ControlKeel governance provider for Omnara
type: governance_provider

mcp:
  server: io.github.aryaminus/controlkeel
  command: controlkeel
  args: ["mcp"]

capabilities:
  - validation
  - findings
  - review_gates
  - checkpoint_management
  - git_workflow
  - worktree_management

installation:
  brew: brew tap aryaminus/controlkeel && brew install controlkeel
  npm: npm i -g @aryaminus/controlkeel
  curl: curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh

hooks:
  pre_commit:
    - tool: ck_git_commit
      validation: true
      block_on_blocked_findings: true
  
  pre_push:
    - tool: ck_git_diff
      base_ref: origin/main
      head_ref: HEAD
      validation: true
  
  pre_switch_worktree:
    - tool: ck_worktree_list
      validation: true
```

## Conclusion

The most valuable integration is **CK as an Omnara Provider Extension**, which gives Omnara users access to CK's governance capabilities without switching tools. This leverages both systems' strengths:

- **Omnara**: Remote control, session management, cross-device coordination
- **ControlKeel**: Governance, validation, evidence, review gates

Together they provide a comprehensive solution for governed, remotely-controllable agent work.