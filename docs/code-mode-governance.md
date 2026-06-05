# Code-mode and generated-script governance

Code-mode is for large API surfaces where one MCP tool per endpoint would bloat context. The agent writes a small program against a typed surface, then CK validates the source and requested capabilities before execution.

## Product stance

Use progressive discovery first. Use code-mode only when the task needs compact orchestration across many API operations.

Good fit:

- large OpenAPI/GraphQL/SDK surfaces
- repetitive API workflows that are clearer as code than as dozens of tool calls
- tasks where typed inputs/outputs reduce ambiguity

Poor fit:

- a small set of direct tool calls
- unreviewed filesystem, shell, secrets, deploy, or network access
- saved automation that will run later without revalidation

## Why not load every tool?

Large API catalogs do not translate cleanly into always-loaded tools. Thousands of schemas consume context before the agent starts solving the task. CK's stance:

1. discover capabilities progressively
2. expose compact typed SDKs or type signatures when available
3. execute generated code only inside a governed sandbox
4. capture source, capability grants, logs, egress summary, and result digests as proof artifacts

## CodeModePolicy

`ControlKeel.Runtime.CodeModePolicy` records the policy map consumed by execution posture and runtime exports:

- `sandbox_required`
- `approval_required`
- `default_denied_capabilities`
- `allowed_capabilities`
- `network_allowlist`
- runtime and output limits
- rate policy with `respect_retry_after`
- expected proof artifacts

`CodeModePolicy` does not execute code. It defines the contract that execution surfaces must honor.

## `ck_execute_code`

`ck_execute_code` is the guarded MCP execution surface for generated code.

Current constraints:

- supports `javascript` and `python`
- supports Docker sandbox only
- refuses local host execution
- validates source before execution
- denies filesystem, secrets, shell, and deploy capabilities
- blocks network until an enforcing egress runtime exists
- bounds runtime and output size
- supports `dry_run` for planning

The important boundary: generated code is always untrusted until CK validation and review approve the capabilities it requests.

## Operating checklist

Before accepting code-mode output:

1. Confirm the brief needs code-mode rather than direct tools.
2. Load only the needed schema, SDK, or skill resources.
3. Run `ck_validate` on generated source and requested capabilities.
4. Require explicit approval for write APIs, network, deploy, shell, secrets, regulated data, or high-risk actions.
5. Keep concurrency, retries, runtime, and output bounded.
6. Respect upstream rate limits and `retry-after` headers.
7. Persist proof artifacts for reuse and audit.
8. Revalidate saved scripts after model, provider, tool, policy, SDK, or API changes.

## Server-side requirements

If your API is exposed to agents through code-mode, design the server as if generated clients will retry, loop, and partially fail:

- rate limit aggressively
- make write operations idempotent where possible
- require scoped credentials
- log by run/task/session identifiers
- expose safe dry-run or preview endpoints for destructive operations
- return actionable errors instead of forcing agents to infer state

Code-mode is a compact plan format, not a permission grant.
