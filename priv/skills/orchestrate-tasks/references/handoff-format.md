# Handoff Format

Workers and verifiers produce a handoff document when they complete. This is the
only communication channel between a worker and its planner.

## Structure

```markdown
# Handoff: <task-name>

## Status
<completed | failed | blocked>

## What was done
<1-5 bullets describing the actual changes made>

## Files changed
- `path/to/file.ex`: <what changed and why>
- `path/to/test.exs`: <what was tested>

## Acceptance criteria met
- [x] <criterion 1>
- [x] <criterion 2>
- [ ] <criterion not met> — <why>

## Test results
<mix test output summary>

## Issues encountered
- <any blockers, unexpected complexity, or things the planner should know>

## Recommendations for planner
<suggestions for follow-up tasks, verifications, or adjustments>
```

## Rules

- **Be specific, not narrative.** "Added `validate_email/1` to `Accounts` module" not "improved validation".
- **Include test evidence.** Every completed worker must include test output.
- **Flag blocked criteria.** If acceptance criteria are not met, explain why and what the planner should do.
- **No code dumps.** The handoff summarizes changes; the actual code is in the repo.
- **Be concise.** A good handoff fits in one screen. If it doesn't, the task was too broad.
