# Deep Code Quality Checklist

Walk this checklist during a deep code quality review. Each item maps to a
`ck_finding` rule ID. Use `ck_validate` for automated scanning, then manually
apply these structural checks.

## File Size and Decomposition

- **1000-line threshold**: Has any file crossed 1000 lines due to this change?
  Rule: `code_quality.file_size`. Severity: high.
  Check: `wc -l <file>`. If approaching or crossing 1000, recommend decomposition.

- **Module cohesion**: Does each module have a single clear responsibility?
  If a module handles auth, formatting, and API calls, flag for extraction.

- **Function length**: Are any functions longer than 50 lines?
  Long functions often hide missing abstractions. Recommend extraction.

## Spaghetti and Branching

- **Ad-hoc conditionals**: Are new `if`/`case`/`cond` branches added to unrelated flows?
  Rule: `code_quality.spaghetti_condition`. Severity: medium to high.
  Prefer: dedicated abstraction, helper, state machine, or separate module.

- **Feature flags in shared code**: Are feature-specific checks scattered across general-purpose modules?
  Rule: `code_quality.wrong_layer`. Severity: medium.
  Prefer: isolate behind a dedicated abstraction.

- **One-off booleans or nullable modes**: Do new flags complicate existing control flow?
  Consider whether a typed model or explicit dispatcher would eliminate the branching.

- **Narrow edge-case handling**: Is special-case logic inserted in the middle of an already busy function?
  Recommend extracting to a helper or restructuring the flow.

## Abstraction Quality

- **Unnecessary abstractions**: Are there wrappers, identity functions, or pass-through helpers that add indirection without clarity?
  Rule: `code_quality.unnecessary_abstraction`. Severity: medium.
  Prefer: delete the layer of indirection.

- **Missing abstractions**: Are there repeated conditionals or similar patterns that signal a missing model?
  Rule: `code_quality.missing_abstraction`. Severity: medium.
  Prefer: extract a typed model, helper, or dispatcher.

- **Thin wrappers**: Does an abstraction merely call through to another function without adding logic?
  Recommend: inline the call unless the wrapper provides a clear naming or boundary benefit.

- **Magic handling**: Are generic mechanisms (dynamic dispatch, reflection-like patterns) used where simple data-shape assumptions would be clearer?
  Rule: `code_quality.magic_handling`. Severity: medium.
  Prefer: explicit typed models.

## Type Boundaries

- **Unnecessary casts**: Are there type casts that obscure the real contract?
  Rule: `code_quality.type_boundary`. Severity: low to medium.
  Prefer: make the boundary explicit.

- **Loose optionality**: Are optional params or nil returns used where the invariant is actually clear?
  Prefer: explicit types that encode the real state.

- **Ad-hoc object shapes**: Are data structures loosely shaped rather than explicitly typed?
  Prefer: structs, typed schemas, or shared contracts.

## Layering and Ownership

- **Feature logic in shared paths**: Is feature-specific logic in general-purpose modules?
  Rule: `code_quality.wrong_layer`. Severity: medium to high.
  Prefer: move to a dedicated module behind the right boundary.

- **Canonical helper duplication**: Is a new helper created when the codebase already has a canonical utility for the job?
  Rule: `code_quality.duplicate_logic`. Severity: medium.
  Prefer: reuse the existing helper.

- **Implementation details leaking through APIs**: Are internal data shapes exposed through public interfaces?
  Recommend: define explicit API contracts.

## Orchestration

- **Sequential when parallel is simpler**: Is independent work serialized for no reason?
  Rule: `code_quality.orchestration`. Severity: low to medium.
  Prefer: parallel execution for independent work.

- **Non-atomic related updates**: Can related updates leave state half-applied?
  Prefer: more atomic structure (transaction, batch, single operation).

## Code Judo Opportunities

For each change, explicitly ask:

- Can this be reframed so fewer concepts, branches, or helper layers are needed?
- Is there a reorganization that uses the existing architecture more effectively?
- Can whole categories of complexity be deleted rather than rearranged?
- Does the change improve or worsen the local architecture?
- Is this the simplest implementation that solves the actual task?

**Priority order** for findings:
1. Structural quality regressions (file size, spaghetti)
2. Missed opportunities for dramatic simplification
3. Boundary and abstraction problems
4. Layering and ownership issues
5. Type boundary concerns
6. Legibility and maintainability
