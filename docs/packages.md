# ControlKeel Packages and Distribution

This document provides a complete overview of all ControlKeel packages, their purposes, and when to use each one.

## Package Categories

ControlKeel distributes software through three main categories:

### 1. Bootstrap Package
**Package:** `@aryaminus/controlkeel`  
**Purpose:** Main installer for the ControlKeel CLI  
**When to use:** First-time installation, always required  
**Install:** `npm i -g @aryaminus/controlkeel` or `brew install controlkeel`

This is the foundation package that installs the native ControlKeel binary. All other packages depend on this being installed first.

### 2. Companion Packages
Published npm packages that integrate ControlKeel with specific agent hosts.

| Package | Host | Purpose | Install |
|---------|------|---------|---------|
| `@aryaminus/controlkeel-opencode` | OpenCode | Native plugin integration for OpenCode | Add `"plugin": ["@aryaminus/controlkeel-opencode"]` to `opencode.json` |
| `@aryaminus/controlkeel-pi-extension` | Pi | Extension for Pi builds with npm support | `pi install npm:@aryaminus/controlkeel-pi-extension` |

**When to use companion packages:**
- When you want direct package-manager integration with your host
- When you prefer published packages over repo-local installs
- For teams using package manager standardization

**Note:** You should still run `controlkeel attach <host>` after installing companion packages to get the full repo-local experience with commands, agents, and MCP config.

### 3. Distribution Bundles (dist/)
Generated bundles for specific hosts and runtimes, exported via `controlkeel attach <host>` or `controlkeel runtime export <target>`.

#### Host Native Bundles
These bundles provide repo-local integration for specific agent hosts:

| Bundle | Host | Install Command | What It Provides |
|--------|------|-----------------|------------------|
| `opencode-native` | OpenCode | `controlkeel attach opencode` | `.opencode/` directory with skills, commands, agents, MCP config |
| `pi-native` | Pi | `controlkeel attach pi` | `.pi/` directory with planning, commands, MCP config |
| `claude-plugin` | Claude Code | `controlkeel attach claude-code` | Claude plugin with hooks, MCP config, command prompts |
| `codex-plugin` | Codex CLI | `controlkeel attach codex-cli` | Codex plugin with skills, hooks, commands, custom agents |
| `copilot-plugin` | GitHub Copilot | `controlkeel attach copilot` | Copilot plugin with hooks, commands, review tools |
| `cursor-native` | Cursor | `controlkeel attach cursor` | `.cursor/` directory with skills, rules, commands, hooks |
| `windsurf-native` | Windsurf | `controlkeel attach windsurf` | Hooks, workflows, commands, MCP config |
| `continue-native` | Continue | `controlkeel attach continue` | Prompts, command prompts, MCP server config |
| `cline-native` | Cline | `controlkeel attach cline` | Rules, workflows, commands, hooks |
| `goose-native` | Goose | `controlkeel attach goose` | Commands, workflow recipes, extension YAML |
| `augment-native` | Augment | `controlkeel attach augment` | Workspace commands, subagents, rules, MCP config |
| `devin-terminal-native` | Devin for Terminal | `controlkeel attach devin-terminal` | `.devin/` directory with MCP, hooks, skills, agents |
| `warp-native` | Warp | `controlkeel attach warp` | `.warp/` directory with skills, MCP config, AGENTS.md |
| And many more... | See `controlkeel attach --list` | | |

#### Runtime Bundles
Headless runtime exports for cloud and CI/CD environments:

| Bundle | Runtime | Export Command | Use Case |
|--------|---------|----------------|----------|
| `devin-runtime` | Devin (hosted) | `controlkeel runtime export devin` | Cloud Devin environments |
| `open-swe-runtime` | Open SWE | `controlkeel runtime export open-swe` | Open SWE headless runs |
| `executor-runtime` | Executor | `controlkeel runtime export executor` | Custom executor runtimes |
| `virtual-bash-runtime` | Virtual Bash | `controlkeel runtime export virtual-bash` | Sandboxed bash environments |
| `cloudflare-workers-runtime` | Cloudflare Workers | `controlkeel runtime export cloudflare-workers` | Cloudflare Workers deployments |
| `warp-oz-runtime` | Warp Oz | `controlkeel runtime export warp-oz` | Warp cloud agents and schedules |

#### Framework Adapters
Integration bundles for framework-level governance:

| Bundle | Framework | Purpose |
|--------|-----------|---------|
| `framework-adapter` | Various | Base adapters for framework integration |
| `forge-acp` | Forge | ACP (Agent Control Protocol) integration |

#### Special Bundles
Utility and compatibility bundles:

| Bundle | Purpose |
|--------|---------|
| `vscode-companion` | VS Code extension for browser-based review |
| `github-repo` | GitHub repository integration assets |
| `instructions-only` | Minimal instruction-only bundles |
| `provider-profile` | Provider configuration profiles |
| `open-standard` | Portable AgentSkills-compatible bundles |

## Installation Patterns

### Pattern 1: Standard Setup (Recommended)
```bash
# 1. Install ControlKeel CLI
npm i -g @aryaminus/controlkeel

# 2. Attach to your host
controlkeel attach <host>  # e.g., controlkeel attach opencode
```

### Pattern 2: Package Manager Integration
```bash
# 1. Install ControlKeel CLI
npm i -g @aryaminus/controlkeel

# 2. Install companion package (if available for your host)
# For OpenCode:
# Add "plugin": ["@aryaminus/controlkeel-opencode"] to opencode.json

# 3. Still run attach for full repo-local experience
controlkeel attach <host>
```

### Pattern 3: Runtime Export
```bash
# 1. Install ControlKeel CLI
npm i -g @aryaminus/controlkeel

# 2. Export runtime bundle for headless environment
controlkeel runtime export <runtime>  # e.g., controlkeel runtime export devin
```

## Package Versioning

- **Bootstrap package** (`@aryaminus/controlkeel`): Follows main CK version (e.g., 0.3.4)
- **Companion packages**: Follow main CK version (e.g., 0.2.47)
- **Dist bundles**: Generated dynamically, version tracked in bundle metadata

All packages are synchronized to the same CK release to ensure compatibility.

## Security and Supply Chain

All ControlKeel packages are published from the official GitHub repository:

- **Source**: https://github.com/aryaminus/controlkeel
- **Bootstrap npm**: https://www.npmjs.com/package/@aryaminus/controlkeel
- **Companion packages**: Published from `controlkeel/dist/` directories
- **Security**: See [SECURITY.md](https://github.com/aryaminus/controlkeel/blob/main/packages/npm/controlkeel/SECURITY.md) for bootstrap package security details

## Troubleshooting Packages

### Issue: Package not found on npm
**Solution:** Ensure you're using the correct package name:
- Bootstrap: `@aryaminus/controlkeel` (not `controlkeel`)
- OpenCode: `@aryaminus/controlkeel-opencode`
- Pi: `@aryaminus/controlkeel-pi-extension`

### Issue: Attach command not working
**Solution:** 
1. Ensure ControlKeel CLI is installed: `controlkeel --version`
2. Run doctor: `controlkeel attach doctor`
3. Check host-specific documentation in [direct-host-installs.md](direct-host-installs.md)

### Issue: Companion package install succeeds but CK not available in host
**Solution:**
1. Run `controlkeel attach <host>` to get repo-local config
2. Restart the host application
3. Check host-specific MCP configuration

### Issue: Version mismatch between packages
**Solution:** All packages should use the same CK version. Update all packages:
```bash
npm update -g @aryaminus/controlkeel
# Update companion packages through your host's package manager
# Re-run controlkeel attach <host> to sync dist bundles
```

## Development and Building Packages

For information on how packages are built and published, see:

- [release-verification.md](release-verification.md) - Release process and verification
- [support-matrix.md](support-matrix.md) - Complete integration catalog
- [direct-host-installs.md](direct-host-installs.md) - Detailed install instructions

## Quick Reference

| I want to... | Command |
|-------------|---------|
| Install ControlKeel | `npm i -g @aryaminus/controlkeel` |
| Attach to my host | `controlkeel attach <host>` |
| List available hosts | `controlkeel attach --list` |
| Export runtime bundle | `controlkeel runtime export <runtime>` |
| Check attachment health | `controlkeel attach doctor` |
| Update ControlKeel | `controlkeel update` |
| Get help | `controlkeel help` |

For host-specific installation details, see [direct-host-installs.md](direct-host-installs.md).