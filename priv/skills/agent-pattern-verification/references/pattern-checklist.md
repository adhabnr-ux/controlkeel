# Agent Pattern Checklist

Detailed patterns and examples for agent pattern verification checks.

## Loop Safety Patterns

### Python Patterns

#### `while True` without break

**Pattern:**
```python
# ❌ Issue - No break condition
while True:
    result = process()
    if result.success:
        return result
    # Never breaks on failure - infinite loop
```

**Pattern:**
```python
# ✅ Pass - Has break condition
while True:
    result = process()
    if result.success:
        return result
    if attempt_count >= MAX_ATTEMPTS:
        break
    attempt_count += 1
```

#### Recursive functions without base case

**Pattern:**
```python
# ❌ Issue - No base case or depth limit
def process_node(node):
    for child in node.children:
        process_node(child)
```

**Pattern:**
```python
# ✅ Pass - Has base case and depth limit
def process_node(node, depth=0, max_depth=100):
    if depth > max_depth:
        return
    for child in node.children:
        process_node(child, depth + 1, max_depth)
```

### TypeScript/JavaScript Patterns

#### `while (true)` without break

**Pattern:**
```typescript
// ❌ Issue - No break condition
while (true) {
  const result = await process();
  if (result.success) {
    return result;
  }
  // Never breaks on failure
}
```

**Pattern:**
```typescript
// ✅ Pass - Has break condition
while (true) {
  const result = await process();
  if (result.success) {
    return result;
  }
  if (attemptCount >= MAX_ATTEMPTS) {
    break;
  }
  attemptCount++;
}
```

### Go Patterns

#### `for {}` without break

**Pattern:**
```go
// ❌ Issue - No break or return
for {
    result := process()
    if result.Success {
        return result
    }
    // Never breaks on failure
}
```

**Pattern:**
```go
// ✅ Pass - Has break condition
for {
    result := process()
    if result.Success {
        return result
    }
    if attemptCount >= maxAttempts {
        break
    }
    attemptCount++
}
```

## Retry Limit Patterns

### Python - Tenacity

**Pattern:**
```python
# ❌ Issue - No stop parameter
@retry
def api_call():
    return requests.get(url)
```

**Pattern:**
```python
# ✅ Pass - Has stop parameter
@retry(stop=stop_after_attempt(3))
def api_call():
    return requests.get(url)
```

### Python - Backoff

**Pattern:**
```python
# ❌ Issue - No max_tries
@backoff.on_exception(backoff.expo, requests.exceptions.RequestException)
def api_call():
    return requests.get(url)
```

**Pattern:**
```python
# ✅ Pass - Has max_tries
@backoff.on_exception(backoff.expo, requests.exceptions.RequestException, max_tries=3)
def api_call():
    return requests.get(url)
```

### Python - urllib3

**Pattern:**
```python
# ❌ Issue - No total parameter
retry = urllib3.Retry()
http = urllib3.PoolManager(retries=retry)
```

**Pattern:**
```python
# ✅ Pass - Has total parameter
retry = urllib3.Retry(total=3)
http = urllib3.PoolManager(retries=retry)
```

### JavaScript/TypeScript - async-retry

**Pattern:**
```typescript
// ❌ Issue - No retries option
const result = await retry(async () => {
  return await apiCall();
});
```

**Pattern:**
```typescript
// ✅ Pass - Has retries option
const result = await retry(async () => {
  return await apiCall();
}, { retries: 3 });
```

### JavaScript/TypeScript - p-retry

**Pattern:**
```typescript
// ❌ Issue - No retries option
const result = await pRetry(async () => {
  return await apiCall();
});
```

**Pattern:**
```typescript
// ✅ Pass - Has retries option
const result = await pRetry(async () => {
  return await apiCall();
}, { retries: 3 });
```

### Custom Retry Loops

**Pattern:**
```python
# ❌ Issue - No counter
while True:
    try:
        return api_call()
    except Exception:
        continue
```

**Pattern:**
```python
# ✅ Pass - Has counter with max check
attempt = 0
while attempt < MAX_RETRIES:
    try:
        return api_call()
    except Exception:
        attempt += 1
        continue
```

## Tool Registry Patterns

### Python - LangChain Decorator

**Definition:**
```python
@tool
def search_web(query: str) -> str:
    """Search the web for information."""
    return search_engine.search(query)
```

**Prompt reference:**
```markdown
You have access to the following tools:
- search_web: Search the web for information
```

**Extracted name:** `search_web`

### Python - OpenAI Function Schema

**Definition:**
```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {...}
    }
}]
```

**Prompt reference:**
```markdown
Available tools:
- get_weather: Get current weather
```

**Extracted name:** `get_weather`

### Python - LangGraph ToolNode

**Definition:**
```python
from langgraph.prebuilt import ToolNode

tools = [search_web, get_weather, calculate]
tool_node = ToolNode(tools)
```

**Prompt reference:**
```markdown
You have access to: search_web, get_weather, calculate
```

**Extracted names:** `search_web`, `get_weather`, `calculate`

### TypeScript - OpenAI Function Schema

**Definition:**
```typescript
const tools = [{
  type: "function",
  function: {
    name: "get_weather",
    description: "Get current weather",
    parameters: {...}
  }
}];
```

**Prompt reference:**
```markdown
Available tools:
- get_weather: Get current weather
```

**Extracted name:** `get_weather`

### Hallucinated Tool Example

**Prompt reference:**
```markdown
You have access to:
- execute_sql: Execute SQL queries
- search_web: Search the web
- analyze_data: Analyze data
```

**Tool definitions:**
```python
tools = [search_web, analyze_data]  # execute_sql not defined
```

**Finding:** ❌ Issue - Hallucinated tool `execute_sql` referenced in prompt but not defined

### Undocumented Tool Example

**Tool definitions:**
```python
tools = [search_web, get_weather, calculate]
```

**Prompt reference:**
```markdown
You have access to:
- search_web: Search the web
- get_weather: Get current weather
```

**Finding:** ⚠️ Warning - Tool `calculate` defined but not documented in prompt

## Context Size Patterns

### System Prompt Size

**Pattern:**
```python
# Calculate token estimate
system_prompt_content = open("system.md").read()
token_estimate = len(system_prompt_content) / 4

if token_estimate > 8000:
    # ❌ Issue - System prompt too large
    record_finding("system_prompt_too_large", severity="issue")
elif token_estimate > 4000:
    # ⚠️ Warning - System prompt approaching limit
    record_finding("system_prompt_large", severity="warning")
```

### Tool Description Size

**Pattern:**
```python
# Calculate single tool description size
tool_description = tool_schema["description"]
token_estimate = len(tool_description) / 4

if token_estimate > 1000:
    # ❌ Issue - Tool description too large
    record_finding("tool_description_too_large", severity="issue")
elif token_estimate > 500:
    # ⚠️ Warning - Tool description large
    record_finding("tool_description_large", severity="warning")
```

### Combined Tool Descriptions

**Pattern:**
```python
# Calculate combined tool descriptions size
total_tool_tokens = sum(
    len(tool["description"]) / 4
    for tool in tools
)

if total_tool_tokens > 4000:
    # ❌ Issue - Combined tool descriptions too large
    record_finding("combined_tool_descriptions_too_large", severity="issue")
elif total_tool_tokens > 2000:
    # ⚠️ Warning - Combined tool descriptions large
    record_finding("combined_tool_descriptions_large", severity="warning")
```

## LangGraph Cycle Analysis

### Infinite Cycle Detection

**Pattern:**
```python
# ❌ Issue - Cycle with no path to END
workflow = StateGraph(AgentState)
workflow.add_node("agent", agent_node)
workflow.add_node("tools", tool_node)

# Creates cycle: agent -> tools -> agent
workflow.add_edge("agent", "tools")
workflow.add_edge("tools", "agent")

# No path to END - infinite loop
```

**Finding:** ❌ Issue - Cycle exists between agent and tools with no path to END

### Valid Cycle with Conditional Exit

**Pattern:**
```python
# ✅ Pass - Cycle with conditional path to END
workflow = StateGraph(AgentState)
workflow.add_node("agent", agent_node)
workflow.add_node("tools", tool_node)

workflow.add_edge("agent", "tools")
workflow.add_edge("tools", "agent")

# Conditional edge can route to END
workflow.add_conditional_edges(
    "agent",
    should_continue,
    {
        "continue": "tools",
        "end": END
    }
)
```

### Dead-End Node Detection

**Pattern:**
```python
# ⚠️ Warning - Node with no outgoing edges
workflow = StateGraph(AgentState)
workflow.add_node("agent", agent_node)
workflow.add_node("tools", tool_node)
workflow.add_node("cleanup", cleanup_node)

workflow.add_edge("agent", "tools")
workflow.add_edge("tools", "cleanup")
# cleanup has no outgoing edges and is not END
```

**Finding:** ⚠️ Warning - Node `cleanup` has no outgoing edges and is not END

## Framework Detection Patterns

### LangGraph Detection

**Python imports:**
```python
from langgraph.graph import StateGraph, END
from langgraph.prebuilt import ToolNode
```

**Config files:**
- `langgraph.json`

### CrewAI Detection

**Python imports:**
```python
from crewai import Agent, Task, Crew
```

**Config files:**
- `crew.yaml`

### AutoGen Detection

**Python imports:**
```python
from autogen import AssistantAgent, UserProxyAgent
```

### LangChain Detection

**Python imports:**
```python
from langchain.agents import AgentExecutor
from langchain.tools import Tool
```

### Custom Agent Detection

**Direct SDK usage:**
```python
import openai
import anthropic
```

No framework-specific imports detected.