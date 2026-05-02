# MCP Auto-Discovery Feature

## Overview

Added MCP auto-discovery capability to ControlKeel, enabling progressive discovery of MCP server tools without manual configuration. This feature aligns with CK's philosophy of progressive discovery and enhances MCP integration without adding execution concerns.

## What Was Added

### 1. MCP Discovery Module
**File**: `lib/controlkeel/mcp/discovery.ex`

A new module that implements MCP server tool discovery:

- **`discover/2`**: Main discovery function that queries an MCP server's `tools/list` endpoint
- **`validate_server/2`**: Validates that a server URL is accessible and responds to MCP protocol
- **Transport support**: 
  - HTTP-based discovery (implemented using Erlang's built-in `:httpc`)
  - stdio-based discovery (placeholder for future implementation)
- **Auto-detection**: Automatically detects transport type from URL scheme

### 2. MCP Tool for Discovery
**File**: `lib/controlkeel/mcp/tools/ck_mcp_discover.ex`

MCP tool wrapper that exposes discovery functionality via CK's MCP protocol:

- **Tool name**: `ck_mcp_discover`
- **Required parameters**: `server_url`
- **Optional parameters**: `timeout`, `transport`
- **Returns**: Discovered tool schemas with metadata

### 3. Protocol Integration
**File**: `lib/controlkeel/mcp/protocol.ex`

Updated MCP protocol to register the new tool:

- Added `CkMcpDiscover` to tool aliases
- Added `ck_mcp_discover_tool/0` to tool schemas
- Added dispatch handler for `ck_mcp_discover`
- Maintained stable tool ordering

### 4. Test Updates
**File**: `test/controlkeel/mcp/protocol_test.exs`

Updated test expectations to include the new tool in the stable tool list.

**File**: `test/controlkeel/skills_test.exs`

Fixed unrelated test failure by adding missing skill to expected list.

## Usage Example

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "ck_mcp_discover",
    "arguments": {
      "server_url": "http://localhost:3001/mcp",
      "timeout": 10000
    }
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "server_url": "http://localhost:3001/mcp",
    "transport": "http",
    "tools": [
      {
        "name": "tool_name",
        "description": "Tool description",
        "input_schema": {...},
        "original": {...}
      }
    ],
    "total": 5,
    "usage_hint": "Use the discovered tool schemas to understand available capabilities. To register these tools with CK, use the MCP client configuration or skills system."
  }
}
```

## Technical Details

### HTTP Discovery Implementation

Uses Erlang's built-in `:httpc` library for HTTP requests:
- No external dependencies required
- Supports custom timeouts
- Proper JSON-RPC 2.0 protocol compliance
- Error handling for HTTP failures, JSON decode errors, and MCP protocol errors

### Transport Auto-Detection

Automatically detects transport type from URL scheme:
- `http://` or `https://` → HTTP transport
- `stdio://` or `/path/to/executable` → stdio transport (placeholder)
- Default to HTTP for unknown schemes

### Error Handling

Comprehensive error handling with user-friendly messages:
- HTTP connection failures
- HTTP status errors
- JSON decode failures
- MCP protocol errors
- Invalid arguments
- Unsupported transport types

## Future Enhancements

### stdio-Based Discovery

The stdio discovery is currently a placeholder. Future implementation would:
- Spawn a subprocess for the MCP server
- Communicate via stdio using MCP protocol
- Handle process lifecycle and cleanup
- Support credential passing for authenticated MCP servers

### Tool Registration

Currently, discovery only returns tool schemas. Future enhancements could:
- Auto-register discovered tools as CK skills
- Generate skill templates from discovered tools
- Support persistent tool registration across sessions

### Credential Integration

If CK adds credential management in the future, discovery could:
- Accept credentials for authenticated MCP servers
- Pass credentials during discovery requests
- Store discovered server configurations

## Alignment with CK Philosophy

This feature aligns with CK's core principles:

1. **Progressive Discovery**: Agents can discover MCP capabilities on-demand without front-loading all tool schemas
2. **Governance-First**: Discovery is read-only; it doesn't execute tools or modify state
3. **No Execution Concerns**: The feature only discovers capabilities, doesn't run them
4. **Local-First**: Uses built-in Erlang libraries, no external HTTP client dependencies
5. **Stable API**: Follows CK's existing MCP tool patterns and error handling

## Testing

All existing tests pass:
- MCP protocol tests verify tool ordering and schema correctness
- Skills tests validate the full skill catalog
- No breaking changes to existing functionality

## Dependencies

No new dependencies added:
- Uses Erlang's built-in `:httpc` for HTTP requests
- Uses existing `Jason` for JSON encoding/decoding
- Uses existing `URI` for URL parsing