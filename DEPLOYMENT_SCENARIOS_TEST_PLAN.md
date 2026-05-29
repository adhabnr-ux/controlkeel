# ControlKeel Deployment Scenarios Test Plan

## Overview

This document defines a comprehensive testing matrix to ensure ControlKeel works across all deployment and usage scenarios:

1. Local agents + local CK on device
2. Local agents + cloud CK from controlkeel.com  
3. Local agents + self-hosted CK
4. SDK integration (TypeScript)
5. MCP (Model Context Protocol) integration
6. Cloud agents + cloud CK on controlkeel.com
7. Cloud agents + self-hosted CK
8. Mixed and hybrid configurations

## Runtime Modes and Surfaces

ControlKeel supports three runtime modes with placement contracts for 11 surfaces:

**Runtime Modes:**
- `:local` - Governed state and execution stay on operator machine
- `:cloud` - Thin CLI/browser; workloads run in ControlKeel Cloud plane
- `:self_hosted` - Cloud semantics against operator's hosted data plane

**Surfaces with placement contracts:**
- `:db` - Database/storage
- `:mcp` - Model Context Protocol tools
- `:skills` - CK skills and workflows  
- `:hooks` - Event hooks
- `:cli` - Command-line interface
- `:web` - Web UI
- `:memory` - Governed memory/storage
- `:policy` - Policy engine
- `:telemetry` - Telemetry collection
- `:observability` - Monitoring and observability
- `:sdk` - SDK integration

## Current Test Coverage Analysis

### ✅ Already Tested

**Runtime Mode Tests (`test/controlkeel/runtime_mode_test.exs`)**
- ✅ Mode parsing (local, cloud, self_hosted)
- ✅ Placement contract for all surfaces
- ✅ Cloud mode endpoint validation (only controlkeel.com)
- ✅ Self-hosted mode endpoint validation (not controlkeel.com)
- ✅ Missing requirements detection
- ✅ Environment variable vs config precedence

**API Scope Tests (`test/controlkeel_web/controllers/api_scope_test.exs`)**
- ✅ Workspace-scoped API endpoints
- ✅ Service account authentication
- ✅ Cross-workspace isolation

**Self-Host Smoke Test (`scripts/self_host_smoke.sh`)**
- ✅ Self-hosted mode boot with fresh DB
- ✅ Home page response
- ✅ Cloud endpoints mounted
- ✅ Auth protection on sync endpoints

**Cloud Readiness Tests (P0-P4)**
- ✅ Full cloud onboarding flow
- ✅ Org admin UI
- ✅ Real-time enforcement
- ✅ Production hardening
- ✅ Marketing and docs

### ❌ Missing Test Coverage

**Local Agent + Local CK (Default Mode)**
- ❌ Full end-to-end local workflow test
- ❌ Local agent using local CK MCP tools
- ❌ Local agent using local CK skills
- ❌ Local web UI in local mode

**Local Agent + Cloud CK**
- ❌ CLI thin client connecting to cloud
- ❌ Remote execution flow with cloud placement
- ❌ Cloud sync push/pull with local agent
- ❌ Web UI as thin client to cloud

**Local Agent + Self-Hosted CK**  
- ❌ CLI thin client connecting to self-hosted
- ❌ Remote execution flow with self-hosted placement
- ❌ Self-hosted sync push/pull with local agent

**SDK Integration**
- ❌ SDK against cloud (controlkeel.com)
- ❌ SDK against self-hosted endpoint
- ❌ SDK error handling and retry logic
- ❌ SDK rate limit handling

**MCP Integration**
- ❌ MCP tools in local mode
- ❌ MCP tools in cloud mode  
- ❌ MCP tools in self-hosted mode
- ❌ MCP tool scoping by workspace

**Cloud Agents**
- ❌ Cloud agent + cloud CK integration
- ❌ Cloud agent + self-hosted CK integration
- ❌ Cloud agent execution model validation

**Cross-Mode Integration**
- ❌ Migration paths between modes
- ❌ Config switching validation
- ❌ Failover scenarios

## Comprehensive Test Matrix

### Scenario 1: Local Agent + Local CK (Default)

| Component | Test | Status |
|-----------|------|--------|
| Runtime mode | `CONTROLKEEL_RUNTIME_MODE=local` | ✅ Tested |
| CK CLI | `ck goal` command runs locally | ❌ Missing |
| Local web UI | Dashboard renders in local mode | ⚠️ Partial |
| Local MCP tools | Agent can call CK MCP tools | ❌ Missing |
| Local skills | Agent can use CK skills | ❌ Missing |
| Local DB | SQLite operations | ✅ Tested |
| Local memory | ETS-based memory | ⚠️ Partial |

### Scenario 2: Local Agent + Cloud CK

| Component | Test | Status |
|-----------|------|--------|
| Runtime mode | `CONTROLKEEL_RUNTIME_MODE=cloud` | ✅ Tested |
| Cloud endpoint | Must be `controlkeel.com` | ✅ Tested |
| Workspace registration | `/cloud/v1/workspaces/register` | ⚠️ Partial |
| Cloud sync push | `/cloud/v1/sync/push` | ⚠️ Partial |
| Cloud sync pull | `/cloud/v1/sync/pull` | ⚠️ Partial |
| Thin client CLI | CLI delegates to cloud | ❌ Missing |
| Remote execution | Agent uses cloud placement | ❌ Missing |
| Cloud web UI | Web UI as thin client | ❌ Missing |

### Scenario 3: Local Agent + Self-Hosted CK

| Component | Test | Status |
|-----------|------|--------|
| Runtime mode | `CONTROLKEEL_RUNTIME_MODE=self_hosted` | ✅ Tested |
| Custom endpoint | Non-controlkeel.com endpoint | ✅ Tested |
| Self-host boot | Phoenix boot with custom PHX_HOST | ✅ Tested |
| Self-host sync | Push/pull to self-hosted endpoint | ⚠️ Partial |
| Thin client CLI | CLI delegates to self-hosted | ❌ Missing |
| Remote execution | Agent uses self-hosted placement | ❌ Missing |

### Scenario 4: SDK Integration

| Component | Test | Status |
|-----------|------|--------|
| SDK install | `npm install @aryaminus/controlkeel-sdk` | ❌ Missing |
| Cloud connection | SDK to `https://controlkeel.com` | ❌ Missing |
| Self-hosted connection | SDK to custom endpoint | ❌ Missing |
| Sync push | `ck.syncPush()` method | ❌ Missing |
| Sync pull | `ck.syncPull()` method | ❌ Missing |
| Service accounts | SDK SA operations | ❌ Missing |
| Error handling | `ControlKeelError` handling | ❌ Missing |
| Rate limits | Retry-After header handling | ❌ Missing |
| TypeScript types | Type checking | ⚠️ Partial (tsc) |

### Scenario 5: MCP Integration

| Component | Test | Status |
|-----------|------|--------|
| MCP server | CK MCP server starts | ❌ Missing |
| MCP tools | CK tools available to agent | ❌ Missing |
| Local mode MCP | Tools execute locally | ❌ Missing |
| Cloud mode MCP | Tools delegate to cloud | ❌ Missing |
| Self-hosted MCP | Tools delegate to self-hosted | ❌ Missing |
| Workspace scoping | MCP tools respect workspace | ❌ Missing |

### Scenario 6: Cloud Agents + Cloud CK

| Component | Test | Status |
|-----------|------|--------|
| Cloud execution model | Hybrid model validation | ✅ Documented |
| Cloud agent auth | Workspace key authentication | ⚠️ Partial |
| Cloud callback | Runtime callbacks to cloud | ⚠️ Partial |
| Cloud telemetry | Telemetry ingestion | ⚠️ Partial |

### Scenario 7: Cloud Agents + Self-Hosted CK

| Component | Test | Status |
|-----------|------|--------|
| Self-hosted cloud agent | Agent connects to self-hosted | ❌ Missing |
| Custom endpoint auth | Workspace key to custom endpoint | ❌ Missing |
| Self-hosted callbacks | Callbacks to self-hosted endpoint | ❌ Missing |

## Recommended Test Implementation Plan

### Priority 1: Core Local Workflow (Scenario 1)
1. Add integration test for `ck goal` local command
2. Test local MCP tool execution with agent
3. Test local skill usage with agent
4. Validate local web UI functionality

### Priority 2: Cloud Integration (Scenarios 2 & 3)
1. Add thin client CLI integration tests
2. Test remote execution placement
3. Validate cloud sync push/pull workflows
4. Test web UI as thin client

### Priority 3: SDK Integration (Scenario 4)
1. Add SDK integration test suite
2. Test against mock cloud endpoint
3. Validate error handling and retry logic
4. Test rate limit response handling

### Priority 4: MCP Integration (Scenario 5)
1. Add MCP server startup tests
2. Test tool registration and discovery
3. Test tool execution in each mode
4. Validate workspace scoping

### Priority 5: Cloud Agent Scenarios (Scenarios 6 & 7)
1. Add cloud agent integration tests
2. Test execution model in cloud mode
3. Test self-hosted cloud agent connections
4. Validate callback mechanisms

## Test Infrastructure Requirements

1. **Mock Cloud Server**: For testing SDK and cloud client scenarios without real cloud
2. **Test MCP Client**: For validating MCP tool execution
3. **Test Agent Harness**: For simulating agent interactions
4. **Mode Switching Test Suite**: For validating runtime mode transitions
5. **Endpoint Mocking**: For testing various cloud/self-hosted endpoints

## Success Criteria

- ✅ All runtime modes tested end-to-end
- ✅ All surfaces tested in each placement scenario
- ✅ SDK validated against mock and real endpoints
- ✅ MCP integration validated in all modes
- ✅ Cloud agent scenarios validated
- ✅ Migration and failover scenarios tested
- ✅ Documentation updated for each scenario
- ✅ CI/CD pipeline includes scenario tests

## Next Steps

1. Implement Priority 1 tests (local workflow)
2. Add mock cloud server infrastructure
3. Implement SDK integration tests
4. Add MCP integration tests
5. Implement cloud agent scenario tests
6. Add cross-mode migration tests
7. Update documentation with scenario guides
