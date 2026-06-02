# Adaptive Tool Groups

ControlKeel includes automatic tool selection optimization ("Adaptive tool groups") that learns usage patterns over time and provides up to 40-60% token reduction by avoiding unnecessary tool context propagation to the LLMs.

## Overview
As projects scale, exposing every available agent capability (MCP, skills, hooks, etc.) incurs a significant token cost for every single model turn. Adaptive tool groups mitigate this.

## Features
- **Project Type Detection:** Automatically selects smart defaults for tool sets based on language/framework heuristcs.
- **Persistence:** Learns from usage patterns and maintains a persistent tool preference per-project.
- **Seamless Integration:** Works transparently across MCP, CLI, Skills, Web, Hooks, and Plugin paths without requiring manual configuration from the operator.

## Architecture
The adaptive routing evaluates the current task, recent transcript events, and the `ck_context` to filter available tools dynamically. Instead of broad casting 30+ tools, it selects the 5-10 most relevant to the current mission phase.

See `ControlKeel.Distribution.required_mcp_tools/0` for the core toolset, and `ControlKeel.Mcp.Protocol.tool_schemas/0` for extended governance sets.
