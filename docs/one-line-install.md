# One-line setup per agent host

This page lists the **shortest possible command** to wire ControlKeel into each supported agent host. Two paths exist — pick based on whether you've already installed the `controlkeel` binary.

## Path A — Full setup (recommended)

If you've installed the CLI (`brew install controlkeel`, `npm i -g @aryaminus/controlkeel`, or the install script), run the matching one-liner. This installs MCP **plus** hooks, skills, AGENTS.md preamble, completion-review command, and host-specific commands.

| Host | One-liner |
| --- | --- |
| Claude Code | `controlkeel attach claude-code` |
| Cursor | `controlkeel attach cursor` |
| Codex CLI | `controlkeel attach codex-cli` |
| Codex app-server | `controlkeel attach codex-cli` |
| OpenCode | `controlkeel attach opencode` |
| Augment / Auggie | `controlkeel attach augment` |
| Continue | `controlkeel attach continue` |
| Aider | `controlkeel attach aider` |
| Cline | `controlkeel attach cline` |
| Roo Code | `controlkeel attach roo-code` |
| Kiro | `controlkeel attach kiro` |
| Goose | `controlkeel attach goose` |
| Gemini CLI | `controlkeel attach gemini-cli` |
| Letta Code | `controlkeel attach letta-code` |
| Windsurf | `controlkeel attach windsurf` |
| VS Code agent mode | `controlkeel attach vscode` |
| GitHub Copilot | `controlkeel attach copilot` |
| Pi | `controlkeel attach pi` |

These commands are idempotent — re-running them is safe and refreshes the artifacts to the latest version.

## Path B — MCP-only setup (copy-paste, no `controlkeel attach`)

If you only want the MCP tool surface and don't want to install the full CLI, use the host's native MCP-add command:

| Host | One-line copy-paste |
| --- | --- |
| **Claude Code** | `claude mcp add-json controlkeel '{"command":"controlkeel","args":["mcp"]}' --scope local` |
| **Cursor** | Click [Add to Cursor](cursor://anysphere.cursor-deeplink/mcp/install?name=controlkeel&config=eyJjb21tYW5kIjoiY29udHJvbGtlZWwiLCJhcmdzIjpbIm1jcCJdfQ==) — or paste into `.cursor/mcp.json`: `{"mcpServers":{"controlkeel":{"command":"controlkeel","args":["mcp"]}}}` |
| **Codex CLI** | Add to `~/.codex/config.toml`: `[mcp_servers.controlkeel]` then `command = "controlkeel"` and `args = ["mcp"]` |
| **OpenCode** | `opencode mcp add controlkeel controlkeel mcp` |
| **VS Code / Copilot** | Add to `.vscode/mcp.json`: `{"servers":{"controlkeel":{"command":"controlkeel","args":["mcp"]}}}` |
| **Continue** | Add to `~/.continue/config.json` under `mcpServers`. |
| **Aider** | `aider --mcp-server controlkeel:controlkeel:mcp` |

### What you get with Path B vs Path A

Path B gives you the full **governance MCP surface** — every `ck_*` tool (`ck_context`, `ck_validate`, `ck_finding`, `ck_review_submit`, `ck_budget`, etc.). The local session, findings, proofs, memory, budget, and review pipeline all work.

**What you don't get** unless you also run `controlkeel attach <host>`:

- Host-specific **hooks** (SessionStart auto-loading `ck_context`, PreToolUse auto-calling `ck_validate`, UserPromptSubmit blocking on findings).
- Host-specific **skills** in `.claude/skills/`, `.codex/skills/`, `.agents/skills/`.
- The `controlkeel-completion-review` slash command and other host-native commands.
- `AGENTS.md` / `CLAUDE.md` governance preamble.
- ControlKeel **subagent** profiles (when applicable).

### Closing the gap from inside an agent session

If you only ran the Path B copy-paste and want the full governance loop, you have two options:

1. **Run the CLI**: install ControlKeel (`brew install controlkeel`) and run `controlkeel attach <host>`. Idempotent — re-running on top of a Path B install just adds the missing artifacts.
2. **Call `ck_attach` from inside the agent**: the LLM can call the MCP `ck_attach` tool with `{"host":"claude-code"}` and it installs the same artifacts without leaving the session. Same trust boundary as any other MCP write tool — see [docs/cloud-enterprise-roadmap.md](cloud-enterprise-roadmap.md) for the policy model.

## Cloud (optional, after either path)

Once attached, opt into a control plane for cross-host governance:

```bash
# Canonical SaaS
controlkeel cloud connect --enroll https://controlkeel.com

# Or your self-host instance
controlkeel cloud connect --enroll https://govern.acme.com

controlkeel cloud doctor   # verify everything is healthy
```

See [docs/self-hosting.md](self-hosting.md) for running your own controlkeel.com on fly.io.
