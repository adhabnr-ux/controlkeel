# QA and Validation Guide

ControlKeel enforces code correctness through deterministic and human-gated validation rather than LLM vibe checks.

## Deterministic Scanner
Before code is written to disk or merged, it passes through `ck_validate`. The scanner applies:
- Basic AST checks and pattern matching
- Destructive shell command detection
- Governance policies (e.g., OWASP, HIPAA, custom rules)
- Semantic analysis

## Validation Workflow
1. **Pre-flight:** Agent proposes a change or plan via `ck_review_submit` or `ck_validate`.
2. **Scanner Evaluation:** The deterministic scanner evaluates the artifact.
3. **Findings Generation:** Any blocked or warned patterns become actionable findings.
4. **Resolution:** The agent must resolve blocked findings (e.g. by applying auto-fixes or seeking human review) before execution proceeds.

## Benchmarking
Teams can construct local QA benchmark suites based on previous findings.
- `controlkeel benchmark run --suite <suite> --subjects controlkeel_validate`
This executes the local learning loop, ensuring that regression failures are caught consistently over time.
