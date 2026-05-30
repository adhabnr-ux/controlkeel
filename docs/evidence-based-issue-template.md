# Evidence-Based Issue Template

This template enforces the 4-point evidence structure recommended in "Building Pi With Pi" to combat AI-generated issue slop.

## Required Structure

Every issue should include these four elements:

1. **Command run** - What exact command or action was performed?
2. **Expected behavior** - What should have happened?
3. **Actual behavior** - What actually happened instead?
4. **Exact error/log** - The complete error message, stack trace, or log output

## Issue Template

```markdown
## Command Run
[Describe exactly what you did. Include commands, URLs, UI actions.]

## Expected Behavior
[Describe what you expected to happen.]

## Actual Behavior
[Describe what actually happened instead.]

## Exact Error/Log
[Paste the complete error message, stack trace, or relevant log output.]

## Environment
[Optional: OS, version, browser, or other context that might be relevant.]
```

## Validation Helper

You can validate issue content using ControlKeel's validation system:

```elixir
# Validate an issue description meets evidence standards
ck_validate(
  content: issue_description,
  source_type: "issue",
  artifact_type: "repro_steps",
  trust_level: "mixed"
)
```

## Common Anti-Patterns

### ❌ Over-Confident Root Cause Analysis

**Bad:**
```
The issue is clearly caused by a race condition in the session manager. 
We should add mutex locks around session state mutations.
```

**Good:**
```
## Command Ran
POST /api/sessions/create with user_id=123

## Expected Behavior
200 OK with session token

## Actual Behavior  
500 Internal Server Error

## Exact Error
** (FunctionClauseError) no function clause matching in MyApp.SessionManager.create_session/1
```

### ❌ Generic Implementation Strategies

**Bad:**
```
The best approach would be to implement comprehensive retry with exponential backoff,
circuit breaker pattern, and extensive monitoring.
```

**Good:**
```
## Command Ran
POST /api/payment/process with valid payment data

## Expected Behavior
Payment processed successfully

## Actual Behavior
Request times out after 30 seconds

## Exact Error
{:error, :timeout} from Stripe API
```

### ❌ Broad Hypotheses

**Bad:**
```
Login doesn't work. This could be auth flow, session management, CSRF validation,
user database integrity, or frontend event handling issues.
```

**Good:**
```
## Command Ran
Clicked login button with valid credentials

## Expected Behavior
Redirect to dashboard

## Actual Behavior
Nothing happens - no network request sent

## Exact Error
No error in console, no network activity in DevTools
```

## Automated Validation Rules

ControlKeel can automatically flag issues that don't meet evidence standards:

- Missing 4-point structure → `ck_finding(category: "quality", severity: "medium", rule_id: "CK-ISSUE-001")`
- Root cause analysis without evidence → `ck_finding(category: "quality", severity: "high", rule_id: "CK-ISSUE-002")`
- Generic implementation advice → `ck_finding(category: "quality", severity: "low", rule_id: "CK-ISSUE-003")`
- Hallucinated code references → `ck_finding(category: "correctness", severity: "high", rule_id: "CK-ISSUE-004")`

## Integration with Project Workflows

### GitHub Issue Template

Add this to `.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Evidence-based bug report
title: ''
labels: ['bug']
assignees: ''
---

## Command Run
[What exact command or action did you perform?]

## Expected Behavior
[What did you expect to happen?]

## Actual Behavior
[What actually happened instead?]

## Exact Error/Log
[Paste the complete error message, stack trace, or log output.]

## Environment
[Optional: OS, version, browser, or other relevant context.]
```

### Pre-Commit Validation

Add a git hook that validates issue references in commits:

```bash
# .git/hooks/pre-commit
if git diff --cached --name-only | grep -q '\.md$'; then
  # Validate issue references meet evidence standards
  controlkeel validate-issues
fi
```

### Bot Integration

Create a GitHub bot that comments on issues missing the 4-point structure:

```markdown
This issue appears to be missing required evidence. Please update to include:

1. **Command run** - What exact command or action was performed?
2. **Expected behavior** - What should have happened?
3. **Actual behavior** - What actually happened instead?
4. **Exact error/log** - The complete error message, stack trace, or log output

See [Evidence-Based Issue Template](https://github.com/your-repo/docs/evidence-based-issue-template.md) for details.
```

## Training and Onboarding

When onboarding new contributors:

1. Share this template and explain the rationale (combating AI slop)
2. Show examples of good vs. bad issues
3. Explain that root cause analysis is welcome **after** the evidence is provided
4. Encourage contributors to say "I don't know the root cause" rather than guessing

## Continuous Improvement

Track metrics to assess template effectiveness:

- % of issues meeting 4-point structure
- Time to first response for evidence-based vs. non-evidence-based issues
- Resolution rate for issues with complete evidence
- Contributor satisfaction with the template

Use these metrics to refine the template and validation rules over time.