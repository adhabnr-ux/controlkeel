# Issue and PR Validation Guide

This guide provides validation patterns for assessing AI-generated issue and pull request content to maintain signal-to-noise quality in governed projects.

## Problem Context

As described in "Building Pi With Pi," AI-generated contributions (called "clankers") can overwhelm maintainers with low-quality content:

- Only 8% of AI-generated PRs are ultimately merged
- Issues often contain confident but incorrect diagnoses
- AI tends to expand narrow observations into broad hypotheses
- Generic implementation strategies without project-specific context

## Validation Patterns

### Evidence-Based Issue Validation

When validating issue content with `ck_validate`, use `artifact_type: "repro_steps"` and `source_type: "issue"` to assess:

**Required evidence (4-point structure):**
1. **Command run**: What exact command or action was performed?
2. **Expected behavior**: What should have happened?
3. **Actual behavior**: What actually happened instead?
4. **Exact error/log**: The complete error message, stack trace, or log output

**Validation flags:**
- Missing the 4-point structure → warn as incomplete evidence
- Root cause analysis without supporting evidence → block as unverified diagnosis
- Generic implementation suggestions without specific context → warn as lacking specificity
- Hallucinated code references (files/functions that don't exist) → block as inaccurate
- Long lists of possible error classes without narrowing → warn as unfocused

### Pull Request Quality Validation

When validating PR content with `ck_validate`, use `artifact_type: "diff"` and `source_type: "pull_request"` to assess:

**Over-engineering detection:**
- Adds fallback mechanisms without evidence they're needed → warn as unnecessary complexity
- Adds migration logic for data that should never be invalid → block as invariant violation
- Adds extensive debug output without clear rationale → warn as verbosity
- Adds defensive programming for states that should be impossible → block as wrong approach

**Invariant enforcement vs. local workarounds:**
- Pattern: "handle malformed X" → Flag as potential invariant violation
- Preferred: "make malformed X impossible" → Validate as correct approach
- Example: Session log reader that tolerates corruption vs. session log writer that prevents corruption

**Scope validation:**
- PR description mentions unrelated changes → flag as scope creep
- Implementation adds features not described in issue → block as misaligned
- PR includes "nice to have" additions without justification → warn as scope expansion

## Trust Boundary Rules

### Source-Type Classification

Use `ck_validate` with appropriate `source_type` for trust-boundary checks:

- `source_type: "issue"` - Issue tracker content (stricter scrutiny for unverified claims)
- `source_type: "pull_request"` - PR descriptions and code changes (medium scrutiny)
- `source_type: "developer"` - Human-authored content (baseline scrutiny)
- `source_type: "generated"` - Known AI-generated content (strictest scrutiny)

### Trust-Level Assessment

Apply different validation thresholds based on `trust_level`:

- `trust_level: "trusted"` - Approved human contributors, standard validation
- `trust_level: "mixed"` - Mixed human/AI content, enhanced validation for AI sections
- `trust_level: "untrusted"` - New or unknown contributors, full validation with automatic flags

## Governance Integration

### Pre-Submission Validation

Before creating issues or PRs:
1. Run `ck_validate` on the proposed content
2. Address blocked findings (over-confident analysis, hallucinated references)
3. Ensure evidence-based structure (4-point format for issues)
4. Verify code references actually exist in the codebase

### Post-Submission Review

During triage:
1. Use `ck_validate` to assess incoming issues/PRs
2. Flag content with common AI slop patterns for priority adjustment
3. Record findings with `ck_finding` for quality tracking
4. Use vouch systems to whitelist contributors who consistently provide high-quality content

### Volume Management Strategies

For projects overwhelmed by AI-generated content:
- **Deprioritize known agent instances**: Use `ck_finding` to tag and lower priority
- **Require human vouch**: Only accept PRs from accounts with prior human-written issues
- **Evidence gates**: Block issues that don't meet the 4-point evidence structure
- **Specificity filters**: Auto-warn content with generic implementation advice

## Example Validation Scenarios

### Example 1: AI-Generated Issue with Over-Confident Analysis

**Input:**
```
The login failure is clearly caused by a race condition in the session manager.
We should add mutex locks around all session state mutations.
```

**Validation:**
```elixir
ck_validate(
  content: "The login failure is clearly caused by a race condition...",
  source_type: "issue",
  trust_level: "untrusted",
  artifact_type: "repro_steps"
)
# Returns: BLOCKED - Root cause analysis without evidence, generic implementation advice
```

**Finding record:**
```elixir
ck_finding(
  category: "quality",
  severity: "high", 
  rule_id: "CK-ISSUE-001",
  plain_message: "Issue contains confident root cause analysis without supporting evidence. Please provide observed facts using 4-point structure: command run, expected behavior, actual behavior, exact error/log.",
  decision: "block"
)
```

### Example 2: Good Evidence-Based Issue

**Input:**
```
Ran: POST /api/auth/login with valid credentials
Expected: 200 OK with session token
Actual: 500 Internal Server Error
Error: FunctionClauseError in MyApp.Auth.SessionManager.create_session/1
```

**Validation:**
```elixir
ck_validate(
  content: "Ran: POST /api/auth/login with valid credentials...",
  source_type: "issue",
  trust_level: "mixed",
  artifact_type: "repro_steps"
)
# Returns: ALLOWED - Meets 4-point evidence structure
```

### Example 3: Over-Engineered PR

**Input:**
```elixir
def read_session_log(file) do
  # Try primary reader
  case File.read(file) do
    {:ok, content} -> 
      # Add fallback for corrupted data
      case parse_session(content) do
        {:ok, session} -> session
        {:error, :corrupted} ->
          # Attempt recovery
          recover_corrupted_session(content)
      end
    {:error, _} ->
      # Try backup location
      read_backup_session(file)
  end
end
```

**Validation:**
```elixir
ck_validate(
  content: "...code with fallbacks and recovery...",
  source_type: "pull_request",
  artifact_type: "diff",
  kind: "code"
)
# Returns: WARNED - Adds local workarounds for corrupted data instead of preventing corruption
```

**Finding record:**
```elixir
ck_finding(
  category: "architecture",
  severity: "medium",
  rule_id: "CK-ARCH-001",
  plain_message: "PR adds tolerant reader for malformed session data instead of preventing malformed data at write time. Prefer invariant enforcement over local workarounds.",
  decision: "warn"
)
```

## Integration with Existing Skills

- **deslop**: Use after validation to clean identified slop patterns
- **reviewable-pr**: Use after validation to improve PR structure and reviewability
- **investigate**: Use for deep analysis of technical issues after initial validation
- **security-review**: Use for security-sensitive content after quality validation

## Continuous Improvement

Track metrics on validation effectiveness:
- Issue acceptance rate before and after validation
- PR merge rate by source type and trust level
- Time saved by filtering low-quality content early
- Contributor quality scores based on validation history

Use these metrics to refine validation rules and thresholds over time.