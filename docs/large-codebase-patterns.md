# Large Codebase Patterns

Governing agents in massive codebases requires structured contextual awareness to avoid token limit exhaustion and hallucination.

## Context Packing (`ck_context_pack`)
Instead of pulling the entire project history, agents use `ck_context_pack` to fetch targeted sub-task bundles. `ck_context` is reserved for establishing the initial mission state.

## Resource Lifecycle Management (RLM)
Large outputs (like build logs, traces) shouldn't be dumped inline into the LLM context. ControlKeel enforces RLM:
- Use `ck_result_peek` to inspect byte-ranges of logs.
- Treat large outputs as named references rather than blobs.

## Workspace Checkpoints
Agents use `ck_checkpoint_create` and `ck_rollback` around risky or exploratory tasks. In large codebases, this ensures that iterative loops don't corrupt the primary development branch, and un-merged changes can be cleanly reverted if upstream dependencies change.
