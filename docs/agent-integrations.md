# ControlKeel Agent Integrations

This document explains the support model. The exhaustive host and protocol inventory lives in [support-matrix.md](support-matrix.md); package names and release surfaces live in [packages.md](packages.md).

## Support by mechanism

ControlKeel supports agent ecosystems through distinct mechanisms:

- **Native attach** — `controlkeel attach <host>` installs the strongest repo-native CK surface available for that host: MCP config, commands, hooks, skills, plugins, agents, or rules depending on what the host actually supports.
- **Direct host install** — some hosts also have a companion package, plugin, VSIX, or extension path. These are optional; `controlkeel attach <host>` remains the repo-local governance path.
- **Hosted protocol access** — service-account-driven clients can use hosted MCP and minimal A2A instead of local stdio MCP.
- **Runtime export** — headless or governed outer-loop systems receive bundles via `controlkeel runtime export <target>` rather than fake native attach commands.
- **Provider-only** — local or hosted model backends can be used for CK-owned model work without becoming agent hosts.
- **Fallback governance** — unsupported tools can still participate by making changes that CK later validates through findings, proofs, review, and proxy-compatible APIs.

Do not infer support from a name alone. Use [support-matrix.md](support-matrix.md) for the current code-aligned truth.

## Bidirectional execution model

Each integration is modeled in two directions:

| Direction | Values | Meaning |
| --- | --- | --- |
| Agent uses CK | `local_mcp`, `hosted_mcp`, `a2a`, `plugin`, `native_skills`, `rules`, `workflows`, `hooks`, `proxy` | How the external agent reaches CK governance. |
| CK runs agent | `embedded`, `handoff`, `runtime`, `none` | Whether CK can drive or package work for that agent. |
| Autonomy truth | `direct`, `handoff`, `runtime`, `inbound_only` | What CK can honestly supervise. |

Blocked findings and explicit approval constraints stop all modes.

## Current high-confidence attach surfaces

The actively maintained first-class attach families include Claude Code, Codex CLI/app-server family, OpenCode, GitHub Copilot, Augment/Auggie, Pi, VS Code, Warp, Devin for Terminal, and several rules/hooks/MCP-oriented hosts. Their exact files, transports, and parity class are in [support-matrix.md](support-matrix.md).

Use the support matrix for current recommended first paths, trust/restart constraints, and provider-bridge details.

## Hosted MCP and A2A

Hosted MCP uses service-account OAuth and exposes CK tools through:

- `POST /mcp`
- `GET /.well-known/oauth-protected-resource/mcp`
- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `POST /oauth/token`

Minimal A2A uses:

- `GET /.well-known/agent-card.json`
- `GET /.well-known/agent.json`
- `POST /a2a`

Hosted access is a gateway pattern: authn/authz, observability, findings, proofs, and policy gates stay centralized instead of being rebuilt by every downstream tool.

## Runtime exports and orchestration adapters

Runtime exports are for systems where CK prepares a governed bundle but does not pretend there is a native local host. Examples include headless runtimes, outer-loop systems, and orchestration layers that launch another supported agent underneath. Attach CK to the underlying runtime when possible; use runtime export when the agent runs outside the local host model.

## Proxy-compatible clients

CK exposes governed proxy endpoints for OpenAI-style and Anthropic-style traffic. Treat proxy support as API-shape compatibility, not as proof of a full native integration.

| Upstream shape | Path on ControlKeel |
| --- | --- |
| OpenAI Responses API | `/proxy/openai/{proxy_token}/v1/responses` |
| OpenAI Chat Completions | `/proxy/openai/{proxy_token}/v1/chat/completions` |
| OpenAI Embeddings | `/proxy/openai/{proxy_token}/v1/embeddings` |
| OpenAI Models | `/proxy/openai/{proxy_token}/v1/models` |
| Anthropic Messages | `/proxy/anthropic/{proxy_token}/v1/messages` |
| OpenAI Realtime | `/proxy/openai/{proxy_token}/v1/realtime` |

## Fallback governance

Unsupported tools still have a truthful recovery path:

1. bootstrap a governed project
2. let the external tool make changes
3. use `controlkeel findings`, proofs, review, and `ck_validate`
4. use proxy mode when the tool can target compatible provider APIs

That keeps the story honest: not every tool gets a first-class attach command, but many tools can still feed the governance loop.

## Progressive discovery and extension trust

CK avoids front-loading every capability into the agent context. The preferred client pattern is:

1. use `ck_context` for current governed state
2. discover the next needed capability with `ck_skill_list`, MCP resources, or `ck_mcp_discover`
3. load only the skill/resource needed for the task
4. validate high-impact instructions and generated code before execution

Skills, hooks, plugins, and generated runtime bundles are behavior-changing inputs. Review them like automation, especially when they can steer high-impact work.
