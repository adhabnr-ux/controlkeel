# Root-Cause Checklist

Walk this checklist during root-cause analysis. Do not stop at the first
symptom — trace each layer until the actual cause is identified.

## Symptom → Cause Tracing

- **What is the observed failure?** Describe the exact symptom: error message, wrong output, crash, timing issue.
- **Where does it manifest?** File, function, line number. The error location is often not the root cause location.
- **What changed recently?** Check `git log --oneline -10` for the relevant area. Often a recent commit introduced the regression.
- **What is the data flow?** Trace inputs → processing → outputs. Where does the wrong value first appear?

## Common Root Causes

- **Nil / missing value**: A field was not preloaded, a map key was missing, a function returned `nil` unexpectedly.
- **Wrong boundary condition**: Off-by-one, empty list, zero value, first/last element not handled.
- **Race condition**: State read before write completes, async operation not awaited, process not alive.
- **Type mismatch**: String vs atom, integer vs float, struct vs map. Check function heads and pattern matches.
- **Schema migration not run**: Column missing, constraint not applied, index not created.
- **Wrong scope or context**: Function called with the wrong module, variable shadowed, import conflict.
- **Stale cache or compiled code**: Old bytecode, stale process dictionary, cached value not invalidated.
- **External dependency change**: API response format changed, dependency version bumped, config drift.

## Verification

- **Can you reproduce it deterministically?** If not, the root cause is not yet understood.
- **Does the fix address the root cause?** If you fix a symptom without the root cause, the bug will recur in a different form.
- **Are there other code paths with the same root cause?** Search for the pattern across the codebase. If found, record as a `ck_finding` with `correctness.same_root_cause`.
