# Targeted Review Loops

This guide outlines patterns for making targeted, iterative revisions during planning and review, avoiding wholesale rewrites that introduce risk and complexity.

## Core Principle

**Revise, don't rewrite.**

As Luis Sanchez identified in Dillon Mulroy's workflow: "On '<snippet/line X>': <concrete change>. Apply only this and re-emit the affected section — don't rewrite everything."

## The Pattern

### Basic Structure

```
identify target → specify change → apply only to affected section → re-emit → iterate
```

1. **Identify Target**: Pinpoint the specific line, section, or component to change
2. **Specify Change**: Describe exactly what should change
3. **Apply Locally**: Modify only the affected section, not the entire artifact
4. **Re-emit**: Output only the changed section with context
5. **Iterate**: Repeat for additional changes

### Example Prompt

```
On line 45 of the structural plan: "interface AuthController" → 
Change to: "interface AuthController extends BaseController"

Apply only this change and re-emit lines 40-50. Do not rewrite the entire plan.
```

## Benefits

1. **Risk Reduction**: Smaller changes have fewer side effects
2. **Review Efficiency**: Easier to review specific changes than entire rewrites
3. **Context Preservation**: Surrounding context stays stable
4. **Iteration Speed**: Quick turnaround on specific changes
5. **Merge Safety**: Smaller diffs are easier to merge and resolve conflicts

## When to Use Targeted Reviews

### ✅ Good Use Cases

- **Naming changes**: Rename a type, function, or variable
- **Interface adjustments**: Add/remove methods from interfaces
- **Boundary modifications**: Adjust seam boundaries
- **Call stack tweaks**: Add/remove a call in the stack
- **Adapter updates**: Change implementation while keeping interface
- **Constraint additions**: Add a constraint to an existing rule

### ❌ Bad Use Cases

- **Architectural shifts**: Fundamental changes to structure
- **Cross-cutting concerns**: Changes that affect many sections
- **Foundational changes**: Changes to core assumptions
- **Performance redesign**: Major performance overhauls

## ControlKeel Integration

### Pre-Review Validation

Before targeted reviews, validate the current state:

```elixir
ck_validate(
  content: current_plan,
  source_type: "developer",
  artifact_type: "source",
  kind: "code"
)
```

### Change Recording

Record each targeted change as a finding:

```elixir
ck_finding(
  category: "review",
  severity: "low",
  rule_id: "CK-REVIEW-001",
  plain_message: "Targeted revision: Line #{line_number} - #{change_description}",
  decision: "allow",
  metadata: %{
    line: line_number,
    original: original_content,
    revised: revised_content,
    scope: "targeted"
  }
)
```

### Review Submission

Submit targeted changes for review:

```elixir
ck_review_submit(
  review_type: "plan",
  submission_body: "Targeted revision at line #{line_number}: #{change_description}",
  metadata: %{
    change_type: "targeted",
    affected_lines: "#{start_line}-#{end_line}",
    original: original_section,
    revised: revised_section
  }
)
```

## Patterns

### Pattern 1: Line-Specific Changes

**Prompt:**
```
On line 23: "interface UserService" → Change to: "interface UserService extends Service"
Re-emit lines 20-25 only.
```

**Response:**
```typescript
// Lines 20-25
interface Database {
  query(sql: string): Promise<Result[]>
}

interface UserService extends Service {
  getUser(id: string): Promise<User>
}
```

### Pattern 2: Section-Specific Changes

**Prompt:**
```
In the "Call Stack" section, add "Logging.log()" after "Database.insert()"
Re-emit only the Call Stack section.
```

**Response:**
```
Call Stack:
POST /api/users/create
  → UserController.create()
    → UserService.create()
      → Database.insert()
      → Logging.log()
      → Cache.set()
```

### Pattern 3: Interface Additions

**Prompt:**
```
To the "SessionManager" interface, add: "validate(session: Session): boolean"
Re-emit only the SessionManager interface.
```

**Response:**
```typescript
interface SessionManager {
  create(userId: string): Promise<Session>
  get(sessionId: string): Promise<Session | null>
  validate(session: Session): boolean
}
```

### Pattern 4: Boundary Adjustments

**Prompt:**
```
In the "Seams" section, change "PostgresDatabase" to "DatabaseAdapter"
Re-emit only the Seams section.
```

**Response:**
```
Seams:
interface DatabaseAdapter {
  insert(table: string, data: Record<string, unknown>): Promise<void>
  query(table: string, id: string): Promise<Record<string, unknown>>
}
```

## Workflow Integration

### In Planning Phase

Use targeted reviews during structural planning:

```elixir
# 1. Initial structural plan
plan = generate_structural_plan(task)

# 2. Targeted review iterations
plan = targeted_review(plan, "Line 45: Add validation method")
plan = targeted_review(plan, "Call stack: Add logging")
plan = targeted_review(plan, "Interface UserService: extend BaseService")

# 3. Consolidate and validate
ck_validate(content: plan, artifact_type: "source", kind: "code")

# 4. Submit for approval
ck_review_submit(review_type: "plan", submission_body: plan)
```

### In Implementation Phase

Use targeted reviews during code implementation:

```elixir
# After initial implementation
code = implement_plan(plan)

# Targeted code review
code = targeted_review(code, "function authenticate: Add error handling")
code = targeted_review(code, "line 120: Fix type mismatch")

# Validate implementation
ck_validate(content: code, artifact_type: "diff", kind: "code")

# Test and commit
run_tests()
ck_git_commit(message: "Implement auth with targeted review fixes")
```

### In Review Phase

Use targeted reviews during human review:

```elixir
# Reviewer requests specific change
reviewer_feedback = "Line 89: The error message should be more specific"

# Apply targeted fix
code = targeted_review(code, "Line 89: Change error message to include user ID")

# Re-validate
ck_validate(content: code, artifact_type: "diff", kind: "code")

# Update PR
update_pr_description("Applied targeted fix at line 89 per reviewer feedback")
```

## Validation Rules

### Scope Validation

Ensure targeted changes stay within bounds:

```elixir
ck_validate(
  content: change_request,
  artifact_type: "source",
  kind: "code",
  metadata: %{
    validation_rule: "targeted_scope",
    max_affected_lines: 10,
    max_sections: 1
  }
)
```

### Impact Validation

Check that targeted changes don't have unintended effects:

```elixir
ck_validate(
  content: revised_section,
  artifact_type: "diff", 
  kind: "code",
  metadata: %{
    validation_rule: "impact_analysis",
    check_breaking_changes: true,
    check_caller_impact: true
  }
)
```

## Anti-Patterns

### ❌ Scope Creep in Targeted Changes

**Bad:**
```
On line 45: Add validation → Also refactors the entire class structure
```

**Good:**
```
On line 45: Add validation → Only adds the validation method
```

### ❌ Context Rewriting

**Bad:**
```
On line 23: Change interface name → Rewrites all references throughout the file
```

**Good:**
```
On line 23: Change interface name → Only changes the interface definition
```

### ❌ Accumulated Targeted Changes

**Bad:**
```
Apply 50 targeted changes in sequence → Effectively a rewrite
```

**Good:**
```
After 5-10 targeted changes, consolidate and re-validate
```

## Metrics and Tracking

Track targeted review effectiveness:

- **Average changes per session**: Number of targeted revisions
- **Scope adherence**: % of changes that stay within target scope
- **Review time**: Time to review targeted vs. wholesale changes
- **Defect rate**: Bugs introduced by targeted vs. wholesale changes
- **Satisfaction**: Human reviewer preference for targeted changes

## Integration with CK Skills

- **structural-planning-guide**: Use targeted reviews during structural planning
- **agentic-self-correction-loops**: Use targeted corrections in validation loops
- **controlkeel-governance**: Validate targeted changes before application
- **reviewable-pr**: Apply targeted reviews to PR descriptions and code

## Examples

### Example 1: Planning Phase

**Initial Plan:**
```typescript
interface UserService {
  getUser(id: string): Promise<User>
}
```

**Targeted Review:**
```
On line 1: Add "createUser" method to UserService interface
Re-emit only the UserService interface.
```

**Result:**
```typescript
interface UserService {
  getUser(id: string): Promise<User>
  createUser(data: UserData): Promise<User>
}
```

### Example 2: Implementation Phase

**Initial Code:**
```typescript
async function authenticate(credentials: Credentials): Promise<AuthResult> {
  const user = await this.userRepository.findByEmail(credentials.email);
  if (user) {
    return { success: true, user };
  }
  return { success: false };
}
```

**Targeted Review:**
```
On line 3: Add password validation check
Re-emit lines 3-6 only.
```

**Result:**
```typescript
async function authenticate(credentials: Credentials): Promise<AuthResult> {
  const user = await this.userRepository.findByEmail(credentials.email);
  if (user && await this.passwordValidator.validate(credentials.password, user.passwordHash)) {
    return { success: true, user };
  }
  return { success: false };
}
```

### Example 3: Review Phase

**Reviewer Feedback:**
```
The error message on line 45 should include the user ID for debugging
```

**Targeted Fix:**
```
Line 45: "Authentication failed" → "Authentication failed for user ID: ${userId}"
Re-emit lines 44-46 only.
```

## Best Practices

1. **Be Specific**: Identify exact lines, sections, or components
2. **Limit Scope**: Change only what's necessary
3. **Preserve Context**: Keep surrounding structure intact
4. **Re-emit selectively**: Only output the affected section
5. **Validate frequently**: Check after each targeted change
6. **Consolidate periodically**: After several targeted changes, re-validate the whole

## Advanced Patterns

### Pattern: Batch Targeted Changes

When multiple related changes are needed:

```
Apply these targeted changes together:
1. Line 23: Add "extends BaseController"
2. Line 45: Add "protected logger: Logger"
3. Line 67: Change "private" to "protected"

Re-emit the entire class definition.
```

### Pattern: Conditional Targeted Changes

Changes that depend on conditions:

```
If the UserService interface doesn't have a "validate" method, add one.
Re-emit only the UserService interface if changed, otherwise confirm no change.
```

### Pattern: Rollback Targeted Changes

Undo specific targeted changes:

```
Rollback the change made at line 45 in the previous iteration.
Re-emit lines 40-50 with the original content restored.
```

## References

- Luis Sanchez's analysis of Dillon Mulroy's workflow (P4: Targeted Review Loop)
- ControlKeel governance and validation patterns
- Structural planning guide for architectural artifacts