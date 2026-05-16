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

## Design for Agents

A common anti-pattern in MCP adoption is doing 1:1 REST to MCP conversion—taking an existing REST API and exposing each endpoint as a separate MCP tool. As Karan notes, this "just results in horrible things" because it doesn't account for how agents actually orchestrate work.

Another anti-pattern is **splitting large APIs into multiple MCP servers** to avoid context bloat. Matt from Cloudflare encountered this: they had 16 MCP servers for different product suites, but coverage was incomplete (e.g., 6 tools in a server when the total API had 30 endpoints). This doesn't fulfill the goal of making every API a tool for agents—it just shifts the burden to users to select the right server.

Instead, MCP servers should be **designed for agents**:

- **Think in terms of orchestration**: Consider how an agent would compose these tools together to accomplish a goal
- **Provide execution environments**: Like Cloudflare's MCP server, give the model an execution environment and let it orchestrate instead of providing hundreds of individual tools
- **Design for human interaction first**: A good starting point is designing the interface for human use—what you'd want as a human is often close to what an agent needs
- **Use programmatic tool calling**: On the server side, provide execution environments that let agents compose tools via code
- **Leverage rich semantics**: Use MCP-specific features that REST APIs don't have (applications, skills over MCP, tasks, elicitation)

This approach reduces token usage, cuts latency, and is more powerful for composition than the "one tool per endpoint" pattern.

## Rich Semantics and MCP-Specific Features

MCP offers rich semantics that go beyond simple tool invocation. These features are underused but powerful:

- **MCP Applications**: Agents shipping their own interface over MCP server (not through plugins, SDKs, or hardcoded UI). This requires both client and server to understand protocol semantics for rendering and UI.
- **Skills over MCP**: Shipping domain knowledge with the server itself, allowing server authors to continuously update skills without relying on plugin mechanisms or registries.
- **Tasks**: Asynchronous task primitives for long-running operations and agent-to-agent communication.
- **Elicitation**: MCP-specific interaction patterns that go beyond simple request/response.

CK's progressive discovery pattern is compatible with these rich semantics—agents can discover not just tools, but also applications, skills, and task capabilities when needed.

## Server Discovery

Beyond manual configuration, MCP is moving toward automatic server discovery via well-known URLs. This allows crawlers, browsers, and agents to automatically discover whether a website exposes an MCP server without manual configuration.

CK's `ck_mcp_discover` tool is a building block that can be used with such discovery mechanisms—once a server URL is discovered (whether manually or automatically), CK can validate it and enumerate its capabilities.

## MCP as middleware

Matt predicts that MCP will become middleware in frameworks - a lightweight integration that can be enabled with a simple flag. The MCP SDK is becoming super lightweight, and by the end of the year, it may be natively integrated into major TypeScript frameworks (Next.js, etc.).

The pattern Matt describes:
- Frameworks will have native MCP integration
- Developers can add `mcp = true` to expose APIs over MCP
- Generate types from OpenAPI specs automatically
- Clients doing programmatic tool calling can consume entire APIs through one endpoint

This aligns with CK's philosophy: MCP is a protocol that should be easy to integrate, not a heavyweight framework. As the SDK becomes more lightweight, it becomes practical to embed it everywhere, making MCP a standard surface for APIs alongside REST, GraphQL, and CLI.

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

### Relation to progressive discovery

A recurring MCP scalability lesson is that a client should not blindly dump every available tool schema into the model context. `ck_mcp_discover` is a deliberately small primitive that supports a more scalable pattern:

- keep the always-loaded tool surface small
- discover external tool schemas only when the task actually needs them
- treat discovery as read-only and governed (a way to inspect capability, not to execute it)

That aligns with the same progressive-discovery stance described elsewhere in CK: load skills and detailed references on demand, and prefer typed/code-mode execution for large surfaces.

Karan's work at Anthropic reinforces this pattern: instead of loading all tools into context, use **tool search** to defer loading until the model needs it. This can massively reduce tool context usage (as seen in Cloud Code's implementation) and prevents context bloat from becoming a scalability bottleneck.

### Programmatic tool calling with execution environments

For large API surfaces, CK prefers code-mode execution where the model writes code to compose tools instead of making serial tool calls. This pattern, which Karan calls "programmatic tool calling," provides several benefits:

- **Reduced latency**: Instead of the model orchestrating tool calls sequentially (which uses inference), the model writes a script that composes tools together
- **Reduced token usage**: Fewer round-trips between model and tools
- **Better composition**: The model can filter, transform, and combine results in code

The pattern works by giving the model an execution environment (V8 isolate, Python interpreter, Lua, etc.) and having it write code that calls tools. When MCP servers support **structured output** (which declares the return value type), the model can use type information to compose tools more effectively.

CK's code-mode governance supports this pattern through `ControlKeel.Runtime.CodeModePolicy`, which provides a sandboxed execution environment with default-deny capabilities for filesystem, network, secrets, and deploy operations.

### Progressive discovery approaches

There are three main approaches to avoiding context window explosion when dealing with large APIs:

1. **CLI introspection**: Agents use `--help` and subcommand discovery to find the right action. This works well (Cloud Code, OpenAI's CLIs use it) but requires shell access, which limits its applicability in some environments.

2. **Tool search**: Cloud Code's approach uses keyword matching to load a subset of relevant tools (e.g., K=8 tools) into context. While this works (2100 tokens loaded, 500 used), it still loads unused tools and doesn't scale to thousands of endpoints.

3. **Code mode**: Let the agent write code against a typed SDK instead of calling individual tools. This scales to entire APIs (Cloudflare exposes 2,600+ endpoints this way) while keeping token usage minimal. The model generates code against types, and the code is executed in an isolated sandbox.

CK's stance is that code mode is the most scalable approach for large API surfaces, while CLI introspection works well for local coding agents with shell access. Tool search is a useful intermediate pattern but doesn't fully solve the scalability problem.

### SDK and code-mode boundary

For coding agents that generate code against complex APIs, auto-discovery is not
always enough: a typed SDK or code-mode surface can be the smaller and more
reliable working set. MCP auto-discovery remains useful for agent-time
operations, smaller APIs, and incremental schema loading.

The detailed SDK-vs-MCP case study is canonical in
[code-mode-governance.md](code-mode-governance.md). This page focuses on MCP
schema loading and discovery boundaries.

### Structured outputs (`structuredContent`)

When CK responds to tool calls, it returns both:

- a text payload (JSON-encoded)
- a `structuredContent` payload (raw structured map)

This is important for programmatic tool calling and code-mode composition: clients can consume structured results directly instead of re-parsing long strings.

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
