# ControlKeel Token Optimization Guide

This guide helps you optimize token usage when using ControlKeel with AI coding agents, ensuring CK doesn't contribute to net token waste in your workflows.

## Overview

Research shows that **73% of tokens in AI coding workflows are wasted**. ControlKeel provides built-in tools and configuration to help you identify and eliminate token waste in your projects.

### Automatic Optimization: Adaptive Tool Groups

**ControlKeel now includes adaptive tool groups that automatically optimize token usage without manual configuration:**

- **Smart defaults**: Automatically detects your project type (Elixir, Node.js, Rust, etc.) and loads only the tools you're likely to need
- **Usage tracking**: Learns from your actual tool usage patterns over time and optimizes accordingly
- **Zero configuration**: Works out of the box - no need to manually set `CK_TOOL_GROUPS`
- **Per-project preferences**: Remembers your optimal tool groups per project for team consistency

This automatic optimization typically reduces tool schema tokens by 40-60% without any user intervention. The manual configuration options below are still available if you need fine-grained control.

See [docs/ADAPTIVE_TOOL_GROUPS.md](ADAPTIVE_TOOL_GROUPS.md) for full details on adaptive behavior.

## Quick Start

```bash
# Run a comprehensive token audit of your project
controlkeel token audit

# Audit specific areas
controlkeel token audit mode=rules    # Check rule file sizes
controlkeel token audit mode=skills   # Check for duplicate skills
controlkeel token audit mode=tools    # Check tool schema overhead

# Get JSON output for automation
controlkeel token audit format=json
```

## Token Waste Sources

### 1. Skill Duplication (Major Impact)

**Problem**: Skills installed in multiple directories (user-level + project-level + multiple host directories) cause the same skill to be loaded multiple times, wasting tokens.

**Example**: A skill like `controlkeel-governance` might appear in:
- `~/.claude/skills/controlkeel-governance/` (user-level)
- `.claude/skills/controlkeel-governance/` (project-level)
- `.agents/skills/controlkeel-governance/` (project-level)
- `.codex/skills/controlkeel-governance/` (Codex host)
- `.cursor/skills/controlkeel-governance/` (Cursor host)
- And more...

**Impact**: Each duplicate copy wastes tokens every time it's loaded. In our measurements, we found **90,144 tokens of waste** from duplicate skills.

**Solution**:
```bash
# Check for duplicate skills
controlkeel token audit mode=skills

# Remove duplicate skill directories, keeping only one canonical location
# Recommended: Keep skills in .agents/skills/ for ControlKeel projects
rm -rf ~/.claude/skills/
rm -rf .claude/skills/
rm -rf .codex/skills/
# (keep only .agents/skills/)
```

### 2. Rule File Bloat (Medium Impact)

**Problem**: Rule files (AGENTS.md, .cursor/rules/, etc.) grow over time and exceed optimal size targets.

**Target**: Keep rule files under 1,200 words (~2,000 tokens)

**Solution**:
```bash
# Check rule file sizes
controlkeel token audit mode=rules

# Optimize oversized rule files:
# - Convert verbose explanations to 3-word imperatives
# - Delete rules you can't remember writing
# - Extract repeated patterns into skills (loaded only when invoked)
# - Move framework-specific rules to project-level files only
```

### 3. Tool Schema Overhead (Medium Impact)

**Problem**: All CK MCP tool schemas are loaded on every connection, even if unused.

**Solution**: ControlKeel uses **tool groups** by default to reduce token overhead:

- **Default**: `core + governance` groups (60% token reduction)
- **Configuration**: Set via `CK_TOOL_GROUPS` environment variable or app config
- **Available groups**: `core`, `governance`, `observability`, `skills`, `filesystem`, `git`, `checkpoints`, `worktrees`

```bash
# Check tool schema overhead
controlkeel token audit mode=tools

# Customize tool groups for your workflow
export CK_TOOL_GROUPS=core,governance,observability
```

### 4. API Interaction Pattern (Major Impact for Coding Agents)

For coding agents that generate code against complex APIs, prefer typed SDKs or
code-mode surfaces over always-loaded MCP tool catalogs when those catalogs would
consume large parts of the context window. MCP remains appropriate for smaller
tool surfaces and agent-time operations such as summarization, triage, and
interactive user actions.

The detailed monday.com SDK-vs-MCP case study and code-mode operating guidance
live in [docs/code-mode-governance.md](code-mode-governance.md). Keep this guide
focused on token-optimization actions rather than duplicating the full case
study.

### 5. Cost Spike and Context Bloat Monitoring

**Problem**: Per-interaction cost spikes or context bloat can indicate token optimization failures that compound at scale.

**Solution**: Monitor production signals for:
- Per-interaction cost spikes that deviate from baseline
- Context window bloat from progressive discovery failures
- Upstream tool or search regressions after provider updates

**Implementation**: `ControlKeel.Budget.SpendAlerts.check_interaction_spike/4` detects when a single interaction cost exceeds a session baseline by a configurable multiplier (default 3×). Call it after each invocation with the interaction cost and your expected baseline cost per interaction. Spike alerts fire callbacks and are retrievable via `get_alerts/2`.

```elixir
case SpendAlerts.check_interaction_spike(session_id, cost_cents, baseline_cents) do
  {:spike, alert} -> # alert has :type, :severity, :ratio, :message
  {:ok, :normal} -> :ok
end
```

These alerts are stored locally and delivered to registered callbacks. Callers can convert reviewed spike alerts into CK observability artifacts (`obs problems`, failure clusters) or benchmark candidates for regression protection. See [docs/benchmarks.md](benchmarks.md) for production signal integration.

## Configuration

### Tool Groups

Tool groups are configured in `config/runtime.exs` and can be customized:

```elixir
# Default configuration (in config/runtime.exs)
config :controlkeel, :mcp, tool_groups: ["core", "governance"]

# Override via environment variable
export CK_TOOL_GROUPS=core,governance,observability

# Available groups:
# - core: ck_validate, ck_context, ck_context_pack, ck_execute_code, ck_budget, ck_route, ck_mcp_discover, ck_token_audit
# - governance: ck_review_submit, ck_review_status, ck_review_feedback, ck_regression_result, ck_finding, ck_goal, ck_memory_*, ck_delegate, ck_cost_optimizer, ck_deployment_advisor, ck_outcome_tracker
# - observability: ck_observability, ck_experience_*, ck_trace_packet, ck_failure_clusters, ck_monitor_subscribe, ck_tool_health, ck_skill_evolution
# - skills: ck_skill_list, ck_skill_load, ck_skill_validate, ck_load_resources
# - filesystem: ck_fs_*
# - git: ck_git_*
# - checkpoints: ck_checkpoint_*
# - worktrees: ck_worktree_*
```

### Token-Aware Budgeting

The `ck_budget` tool includes optional token overhead analysis:

```json
{
  "session_id": 123,
  "mode": "estimate",
  "include_token_overhead": true,
  "project_root": "/path/to/project"
}
```

This adds a `token_overhead` section to the budget response with:
- Rule file token estimates
- Skill duplication analysis
- Tool schema recommendations

## Integration with CK Commands

### Skills Doctor

The `controlkeel skills doctor` command now includes token optimization warnings:

```bash
controlkeel skills doctor
```

If duplicate skills are found, you'll see:
```
⚠️  TOKEN OPTIMIZATION WARNING:
  Found X duplicate skill copies wasting tokens.
  Run 'controlkeel token audit' for detailed analysis and recommendations.
  Run 'controlkeel token audit mode=skills' to see skill-specific optimization guidance.
```

### Observability Reports

Token overhead recommendations appear in `ck_observability` cost reports, making token waste visible alongside other cost metrics.

## Host-Specific Guidance

### Cursor

- Skills are loaded from `.cursor/skills/` and user-level directories
- Use `controlkeel token audit` to check for duplicates across Cursor-specific directories
- Tool groups apply to Cursor MCP connections

### Claude Desktop/Code

- Skills are loaded from `.claude/skills/` and user-level directories
- Check for duplicates in Claude-specific directories
- Tool groups apply to Claude MCP connections

### Other Hosts (Codex, Roo, Cline, etc.)

- Each host may have its own skills directory (`.codex/skills/`, `.roo/skills/`, etc.)
- Run token audit to identify host-specific duplication
- Tool groups apply regardless of host

## Best Practices

1. **Regular Audits**: Run `controlkeel token audit` periodically to catch token waste early
2. **Single Source of Truth**: Keep skills in one canonical location (`.agents/skills/` recommended)
3. **Rule File Hygiene**: Keep rule files concise and focused
4. **Tool Group Tuning**: Customize tool groups based on your workflow
5. **Budget Integration**: Use `include_token_overhead` in budget checks for comprehensive cost awareness

## Automation

### CI/CD Integration

Add token audits to your CI pipeline:

```yaml
- name: ControlKeel Token Audit
  run: |
    controlkeel token audit format=json > token-audit.json
    # Fail if token waste exceeds threshold
    if jq '.duplicate_token_count > 10000' token-audit.json; then
      echo "Token waste too high!"
      exit 1
    fi
```

### Pre-commit Hooks

Add a pre-commit hook to check for token regression:

```bash
#!/bin/bash
# .git/hooks/pre-commit
controlkeel token audit
if [ $? -ne 0 ]; then
  echo "Token audit failed. Please fix token waste before committing."
  exit 1
fi
```

## Troubleshooting

### "Too many duplicate skills"

**Symptom**: Token audit shows many duplicate skill copies

**Solution**: 
1. Identify which skills are duplicated
2. Choose one canonical location (recommend `.agents/skills/`)
3. Remove duplicates from other locations
4. Update any configuration that points to removed locations

### "Rule file too large"

**Symptom**: Token audit flags rule files as oversized

**Solution**:
1. Review the flagged rule files
2. Extract repeated patterns into skills
3. Convert verbose explanations to concise bullet points
4. Consider splitting large rule files into focused, smaller files

### "Tool schema overhead high"

**Symptom**: Tool schema audit shows high token usage

**Solution**:
1. Review which tool groups you're using
2. Customize `CK_TOOL_GROUPS` to include only necessary groups
3. Consider if you need all tools in every session

## Support

For issues or questions about token optimization:
- Run `controlkeel token audit` for diagnostic information
- Check CK observability reports for token overhead trends
- Review this guide for common optimization patterns

## Related Documentation

- [ControlKeel CLI Reference](#) - Full CLI command reference
- [MCP Protocol Documentation](#) - Tool groups and MCP integration details
