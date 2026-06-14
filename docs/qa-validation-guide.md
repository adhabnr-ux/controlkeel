# QA and Validation Guide

ControlKeel enforces code correctness through deterministic and human-gated validation rather than LLM vibe checks.

## Deterministic Scanner
Before code is written to disk or merged, it passes through `ck_validate`. The scanner applies:
- Basic AST checks and pattern matching
- Destructive shell command detection
- Secret and credential detection in prompts and source
- Sensitive file write detection (`.env`, `.key`, `.pem`, credentials)
- Governance policies (e.g., OWASP, HIPAA, custom rules)
- Semantic analysis

## Enforcement surfaces
The scanner runs through multiple surfaces:
- **MCP tool:** `ck_validate` called by the agent before mutations
- **PreToolUse hooks:** shell commands and sensitive file writes are validated automatically; blocked results produce `permissionDecision: "deny"`
- **API endpoint:** `POST /api/v1/validate` for programmatic callers
- **CLI:** `controlkeel validate --content <text> --kind <kind>`

## Validation Workflow
1. **Pre-flight:** Agent proposes a change or plan via `ck_review_submit` or `ck_validate`.
2. **Scanner Evaluation:** The deterministic scanner evaluates the artifact.
3. **Findings Generation:** Any blocked or warned patterns become actionable findings.
4. **Resolution:** The agent must resolve blocked findings (e.g. by applying auto-fixes or seeking human review) before execution proceeds.
5. **Memory:** Resolved findings are recorded as typed memory for future retrieval.

## Workspace scoping
All API endpoints enforce workspace authorization in service-account/cloud mode. A service account for workspace A cannot read or mutate workspace B's sessions, tasks, findings, proofs, reviews, budget, or memory. Cross-workspace access returns 403 Forbidden. Local unauthenticated mode remains a deliberate single-user passthrough.

## Cloud sync evidence
Cloud sync push/pull is token-authenticated, workspace-scoped, redacted before egress, and idempotent for findings, reviews, digests, and memory records. Workspace ID mismatches are rejected with 403.

## Benchmarking
Teams can construct local QA benchmark suites based on previous findings.
- `controlkeel benchmark run --suite <suite> --subjects controlkeel_validate`
This executes the local learning loop, ensuring that regression failures are caught consistently over time.

External regression results recorded through `ck_regression_result` produce both proof-consumable invocations and memory-retrievable regression records.
