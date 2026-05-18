# Adaptive Tool Groups

ControlKeel's adaptive tool groups feature automatically learns which tools you actually use and optimizes tool group selection without manual configuration.

## Problem Solved

Previously, ControlKeel used static tool group configuration:
- Default: `["core", "governance"]` (21 tools only, 25 tools hidden)
- Users got "tool not found" errors when trying to use hidden tools
- Manual override required via `CK_TOOL_GROUPS` environment variable
- No learning, no auto-detection, no dynamic adjustment

## How Adaptive Tool Groups Work

The adaptive system operates on three levels:

### 1. Smart Defaults (First Use)

When you first use ControlKeel in a project, it intelligently detects project characteristics and selects appropriate tool groups:

- **Elixir/Phoenix projects** (`mix.exs`): Adds `filesystem` and `git` groups
- **Node.js projects** (`package.json`): Adds `filesystem` and `git` groups
- **Rust projects** (`Cargo.toml`): Adds `filesystem` and `git` groups
- **Git repositories** (`.git`): Adds `git` group
- **Projects with tests**: Adds `filesystem` and `git` groups
- **Default**: Adds `filesystem` group for general development

Base groups always included: `core` and `governance`

### 2. Usage Tracking (Learning)

As you work, ControlKeel tracks which tools you actually use:
- Every tool call is recorded per project
- Usage data is retained for 7 days
- Tracking is asynchronous to avoid blocking tool calls
- No configuration required - it just works

### 3. Adaptive Selection (Optimization)

When selecting tool groups, the system checks in order:

1. **Explicit project preference** (if set via `--apply`)
2. **Usage-based suggestions** (if sufficient data exists)
3. **Smart defaults** (based on project type)

This ensures:
- Your explicit preferences are always respected
- The system learns from your actual usage
- New projects get sensible defaults immediately

## Tool Groups

Available tool groups:

- **core**: `ck_validate`, `ck_context`, `ck_context_pack`, `ck_execute_code`, `ck_budget`, `ck_route`, `ck_mcp_discover`, `ck_token_audit`
- **governance**: `ck_review_submit`, `ck_review_status`, `ck_review_feedback`, `ck_regression_result`, `ck_finding`, `ck_goal`, `ck_memory_record`, `ck_memory_search`, `ck_memory_archive`, `ck_delegate`, `ck_cost_optimizer`, `ck_deployment_advisor`, `ck_outcome_tracker`
- **observability**: `ck_observability`, `ck_experience_index`, `ck_experience_read`, `ck_experience_search`, `ck_trace_packet`, `ck_failure_clusters`, `ck_monitor_subscribe`, `ck_tool_health`, `ck_skill_evolution`
- **skills**: `ck_skill_list`, `ck_skill_load`, `ck_skill_validate`, `ck_load_resources`
- **filesystem**: `ck_fs_ls`, `ck_fs_read`, `ck_fs_find`, `ck_fs_grep`
- **git**: `ck_git_status`, `ck_git_diff`, `ck_git_commit`
- **checkpoints**: `ck_checkpoint_create`, `ck_checkpoint_restore`, `ck_checkpoint_list`
- **worktrees**: `ck_worktree_list`, `ck_worktree_switch`

## CLI Commands

### Suggest Optimal Tool Groups

```bash
controlkeel tool groups suggest
```

This analyzes your usage patterns and suggests optimal tool groups for your project.

Output case:
```
Tool Groups Suggestion:
  Suggested groups: ["core", "governance", "filesystem", "git"]
  Reason: Based on 15 unique tools used in this project
  Usage stats:
    Total calls: 42
    Unique tools: 15

To apply this suggestion to your project, run:
  controlkeel tool groups suggest --apply
```

### Apply Suggested Groups

```bash
controlkeel tool groups suggest --apply
```

This saves the suggested groups to your project binding, making them the permanent preference for this project.

### JSON Output

```bash
controlkeel tool groups suggest --format=json
```

## Manual Configuration

If you prefer manual control, you can still use environment variables:

```bash
export CK_TOOL_GROUPS=core,governance,filesystem,git
```

This environment variable takes precedence over adaptive behavior.

Or set it in your runtime configuration:

```elixir
# config/runtime.exs
config :controlkeel, :mcp, tool_groups: ["core", "governance", "filesystem"]
```

## Project Binding

Tool group preferences are stored in your project binding at `controlkeel/project.json`:

```json
{
  "version": 1,
  "project_root": "/path/to/project",
  "tool_groups": ["core", "governance", "filesystem", "git"],
  ...
}
```

This allows:
- Per-project customization
- Version control of preferences
- Team consistency

## Logging

ControlKeel logs tool group decisions for transparency:

```
Adaptive tool groups for myproject: ["core", "governance", "filesystem", "git"] (25/46 tools, 21 excluded)
```

This helps you understand which tools are available and why.

## Benefits

1. **No Manual Configuration**: Works out of the box with smart defaults
2. **Automatic Learning**: Adapts to your actual usage patterns
3. **Reduced Errors**: Fewer "tool not found" errors
4. **Better Performance**: Only loads tools you actually use
5. **Team Consistency**: Project binding preferences can be version-controlled
6. **Transparency**: Clear logging of decisions and usage stats

## Migration from Static Configuration

If you were using static `CK_TOOL_GROUPS` configuration:

1. **Remove the environment variable** - let adaptive behavior take over
2. **Run `controlkeel tool groups suggest`** - see what the system recommends
3. **Apply suggestions** - use `--apply` if you agree with the recommendations
4. **Work normally** - the system will continue to learn and optimize

If you need to override adaptive behavior temporarily:
```bash
CK_TOOL_GROUPS=all controlkeel mcp
```

## Troubleshooting

### "Tool not found" Errors

If you still get "tool not found" errors:

1. Check which groups are active:
   ```bash
   controlkeel tool groups suggest
   ```

2. Apply suggestions to include the tool's group:
   ```bash
   controlkeel tool groups suggest --apply
   ```

3. Or temporarily use all tools:
   ```bash
   CK_TOOL_GROUPS=all controlkeel mcp
   ```

### Reset Usage Tracking

To reset usage tracking for a project:

```elixir
ControlKeel.MCP.ToolGroupTracker.reset_project(project_root)
```

### Clear Project Preference

To remove a project's explicit tool group preference:

Edit `controlkeel/project.json` and remove the `"tool_groups"` field, or delete the file entirely.

## Implementation Details

- **Usage Storage**: ETS table with 7-day retention
- **Tracking**: Asynchronous to avoid blocking tool calls
- **Smart Defaults**: Based on file system detection
- **Priority**: Project preference > Usage data > Smart defaults
- **Logging**: Info-level logs for all decisions

## Future Enhancements

Potential improvements:
- Host-type awareness (Cursor, VS Code, CLI, etc.)
- Task-type awareness (coding, debugging, deployment, etc.)
- Cross-project learning (shared patterns across projects)
- Automatic preference updates based on usage drift