# Agentic Self-Correction Loops

This guide outlines patterns for building agentic loops that let models correct their own mistakes using validation tools, based on Teresa Torres' experience building AI-generated opportunity solution trees.

## Core Insight

**Let the model correct its own mistakes using validation tools as feedback.**

As Teresa Torres discovered: "My core insight was that I could use this same validation code as a tool for the agent. The agent could generate the change set, call the tool, and then get the results. If the change set was invalid, the agent would get instructions on what needed to be fixed. The agent would continue to work until the validation passed."

## The Pattern

### Basic Loop Structure

```
generate → validate → [fail → feedback → generate → validate] → succeed
```

1. **Generate**: Model produces output
2. **Validate**: Validation tool checks output against rules
3. **Feedback**: If validation fails, tool returns specific error instructions
4. **Correct**: Model uses feedback to fix the errors
5. **Repeat**: Loop until validation passes or max turns reached

### Implementation Example

```javascript
async function agenticLoop(initialTask, validator, maxTurns = 5) {
  let currentTask = initialTask;
  let turns = 0;
  
  while (turns < maxTurns) {
    // Generate
    const output = await model.generate(currentTask);
    
    // Validate
    const validationResult = validator.validate(output);
    
    if (validationResult.isValid) {
      return output; // Success
    }
    
    // Feedback
    currentTask = `Fix these errors in your previous output:\n${validationResult.errors.join('\n')}\n\nOriginal task: ${initialTask}`;
    turns++;
  }
  
  throw new Error('Failed to converge after ' + maxTurns + ' turns');
}
```

## ControlKeel Integration

### Using ck_validate as the Validator

ControlKeel's `ck_validate` tool is designed for exactly this pattern:

```elixir
# Generate plan
plan = generate_architectural_plan(task)

# Validate
validation_result = ck_validate(
  content: plan,
  source_type: "generated",
  artifact_type: "source",
  kind: "code"
)

# Self-correction loop
if validation_result.decision == "block" do
  feedback = format_findings(validation_result.findings)
  corrected_plan = generate_correction(feedback, original_plan)
  
  # Validate again
  validation_result = ck_validate(
    content: corrected_plan,
    source_type: "generated",
    artifact_type: "source", 
    kind: "code"
  )
end
```

### Recording Findings for Feedback

When validation fails, use `ck_finding` to record the issue:

```elixir
ck_finding(
  category: "correctness",
  severity: "high",
  rule_id: "CK-LOOP-001",
  plain_message: "Agentic loop required correction: #{error_description}",
  decision: "warn"
)
```

## Best Practices

### 1. Design Clear Validation Rules

Validation rules must be:
- **Specific**: Tell the model exactly what's wrong
- **Actionable**: Provide clear guidance on how to fix
- **Deterministic**: Same input produces same validation result

**Bad validation feedback:**
```
The plan is wrong.
```

**Good validation feedback:**
```
Error: Boundary violation - AuthController directly calls Database.
Fix: Add a Repository seam between AuthController and Database.
```

### 2. Limit Context in Feedback Loops

Teresa found that too much context caused the model to introduce more mistakes. Provide:
- The specific errors to fix
- Minimal context about the larger problem
- Clear instruction on what to correct

### 3. Set Appropriate Turn Limits

Avoid infinite loops by:
- Setting max turns (typically 3-5)
- Monitoring convergence rate
- Escalating to human review if loops don't converge

### 4. Track Loop Effectiveness

Monitor metrics:
- Average turns to convergence
- Failure rate (hits max turns)
- Types of errors that require multiple corrections
- Cost per successful correction

## Example: Tree Diff Validation

From Teresa Torres' experience with opportunity solution trees:

### Problem
Model-generated change sets didn't always produce the claimed final tree due to hidden operations (splits, merges).

### Validation Tool

```javascript
function validateChangeSet(inputTree, outputTree, changeSet) {
  const errors = [];
  
  // Apply change set to input tree
  let reconstructedTree = applyChangeSet(inputTree, changeSet);
  
  // Compare with claimed output
  if (!treesEqual(reconstructedTree, outputTree)) {
    errors.push('Change set does not generate the claimed output tree');
  }
  
  // Check for data loss
  const lostSources = findLostSourceOpportunities(inputTree, outputTree, changeSet);
  if (lostSources.length > 0) {
    errors.push(`Lost source opportunities: ${lostSources.join(', ')}`);
  }
  
  // Check for orphaned nodes
  const orphans = findOrphanedNodes(inputTree, changeSet);
  if (orphans.length > 0) {
    errors.push(`Orphaned nodes after merge: ${orphans.join(', ')}`);
  }
  
  return {
    isValid: errors.length === 0,
    errors
  };
}
```

### Agentic Loop

```javascript
async function generateValidChangeSet(inputTree, newInterviews) {
  let changeSet;
  let turns = 0;
  const maxTurns = 3;
  
  while (turns < maxTurns) {
    // Generate change set
    const result = await model.generate(`
      Generate a change set to update this opportunity tree with new interview content.
      Input tree: ${JSON.stringify(inputTree)}
      New interviews: ${JSON.stringify(newInterviews)}
      
      Output both:
      1. The updated tree
      2. The change set (add, delete, merge, split operations) that generates it
    `);
    
    changeSet = result.changeSet;
    const outputTree = result.tree;
    
    // Validate
    const validation = validateChangeSet(inputTree, outputTree, changeSet);
    
    if (validation.isValid) {
      return { changeSet, outputTree };
    }
    
    // Feedback
    result = await model.generate(`
      Fix these errors in your change set:
      ${validation.errors.join('\n')}
      
      Original input tree: ${JSON.stringify(inputTree)}
      Your previous change set: ${JSON.stringify(changeSet)}
      
      Generate a corrected change set that:
      1. Generates the claimed output tree when applied
      2. Preserves all source opportunities and children
      3. Does not orphan any nodes
    `);
    
    turns++;
  }
  
  throw new Error('Failed to generate valid change set');
}
```

## Common Error Patterns

### 1. Over-Correction

Model introduces new mistakes while fixing old ones.

**Solution**: 
- Provide minimal feedback
- Ask model to only fix specific errors
- Limit the scope of each correction turn

### 2. Infinite Loops

Model keeps making different mistakes without converging.

**Solution**:
- Set strict max turns
- Escalate to human review after failure
- Analyze patterns to improve validation rules

### 3. Context Overflow

Too much context causes model to lose track of the original task.

**Solution**:
- Include original task in each feedback message
- Keep feedback focused and specific
- Use `ck_context_pack` for targeted context retrieval

## Integration with ControlKeel Governance

### Before Loops

1. **Budget Check**: Use `ck_budget` before expensive agentic loops
2. **Context Setup**: Use `ck_context` to load governance state
3. **Route Decision**: Use `ck_route` to determine if agentic loop is appropriate

### During Loops

1. **Validation**: Use `ck_validate` as the validation tool
2. **Finding Recording**: Use `ck_finding` for each correction cycle
3. **Cost Tracking**: Monitor token usage and spend

### After Loops

1. **Success Recording**: Use `ck_outcome_tracker` to record successful corrections
2. **Failure Analysis**: Record patterns when loops fail to converge
3. **Memory Update**: Use `ck_memory_record` to store learned patterns

## Advanced Patterns

### 1. Hierarchical Validation

Validate at multiple levels:
- **Syntax**: Structure/format validation
- **Semantics**: Business logic validation  
- **Integration**: System-level validation

```javascript
const validations = [
  validateSyntax,
  validateSemantics, 
  validateIntegration
];

for (const validator of validations) {
  const result = validator(output);
  if (!result.isValid) {
    return result; // Fail fast on first error
  }
}
```

### 2. Progressive Refinement

Start with coarse validation, progressively refine:

```javascript
// Coarse: high-level structure
validateCoarse(output)
  // If passes, validate details
  .then(() => validateDetails(output))
  // If passes, validate integration
  .then(() => validateIntegration(output));
```

### 3. Parallel Validation

Run multiple validators in parallel:

```javascript
const [syntaxResult, semanticResult, integrationResult] = await Promise.all([
  validateSyntax(output),
  validateSemantics(output),
  validateIntegration(output)
]);
```

## Anti-Patterns

### ❌ Trusting Model Output Without Validation

As Teresa learned: "Claude is back on a short leash. I found a lot of gaps in my implementation in areas where I simply trusted that Claude got it right, when in fact it didn't."

### ❌ Unclear Error Messages

Models need specific, actionable feedback to correct effectively.

### ❌ Unlimited Turn Limits

Always set max turns to prevent infinite loops and cost runaway.

### ❌ Ignoring Loop Failures

When loops fail to converge, escalate to human review rather than proceeding with invalid output.

## Metrics and Monitoring

Track these metrics to assess loop effectiveness:

- **Convergence Rate**: % of loops that succeed within max turns
- **Average Turns**: Mean turns to convergence
- **Cost per Success**: Token cost for successful corrections
- **Error Patterns**: Most common validation failures
- **Escalation Rate**: % of loops requiring human review

## Continuous Improvement

Use loop data to:
1. Identify common error patterns
2. Improve validation rules
3. Refine feedback messages
4. Adjust turn limits
5. Optimize prompt engineering

## References

- Teresa Torres' "Behind the Scenes: Building AI-Generated Opportunity Solution Trees"
- ControlKeel validation tools and governance framework
- "Building Pi With Pi" on the importance of validation over trust