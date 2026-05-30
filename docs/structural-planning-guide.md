# Structural Planning Guide

This guide outlines structural planning patterns for AI-assisted development, based on insights from Dillon Mulroy's workflow and Luis Sanchez's analysis.

## Core Principle

**Plans should be structural artifacts, not prose.**

As Leo Tavares noted: "Types tell the agent what exists, the call graph tells it what's allowed to talk to what. That's the boundary info models otherwise guess at and get wrong. You hand it the architecture instead of hoping it infers it."

## The Structural Artifact

A structural plan includes:

1. **Type API / public interface of the seam**
2. **Call stack / call graph from entrypoint down to the leaf**
3. **Seams (where behavior is injected)**
4. **Adapters (production implementation vs test/in-memory)**

### Example Structure

```typescript
// Type API
interface SessionManager {
  create(userId: string): Promise<Session>
  get(sessionId: string): Promise<Session | null>
  validate(session: Session): boolean
}

// Call Stack
POST /api/auth/login
  → AuthController.login()
    → SessionManager.create()
      → Database.insert()
      → Cache.set()
    → ResponseComposer.success()

// Seams
interface Database {
  insert(table: string, data: Record<string, unknown>): Promise<void>
}
interface Cache {
  set(key: string, value: string): Promise<void>
}

// Adapters
// Production: PostgresDatabase, RedisCache
// Test: InMemoryDatabase, InMemoryCache
```

## Production vs Test Call Graphs

Show the final call graph in two versions — Production and Tests — so the shape is identical and the only thing that changes is the injected layers/adapters (real vs in-memory).

**Production Call Graph:**
```
AuthController.login()
  → SessionManager.create()
    → PostgresDatabase.insert()
    → RedisCache.set()
```

**Test Call Graph:**
```
AuthController.login()
  → SessionManager.create()
    → InMemoryDatabase.insert()
    → InMemoryCache.set()
```

The shape is identical; only the adapters change.

## Planning Workflow (Based on Luis Sanchez's Analysis)

### P1 — Trigger an Architecture Review (Anchored)

```
I'm not happy with the patterns/design of @<file/module>.
Review its integration/composition with @<collaborator>.
Study the patterns in <reference codebases/libs> and tell me where the design's locality/cohesion breaks down.
```

### P2 — Plan as Iterable Text (No Report/File)

```
Don't generate a report or a file: give me the analysis as text in the message so we can iterate on it line by line right here.
```

### P3 — Structural Artifact (The Core) ⭐

```
For each of the <N> options, sketch in <language> pseudocode, concretely and concisely (these are sketches, not final code):
1. Type API / public interface of the seam
2. Call stack / call graph from entrypoint down to the leaf
3. Seams (where behavior is injected)
4. Adapters (production implementation vs test/in-memory)
```

### P3‑bis — Prod‑vs‑Test Call Graph (The Viral Artifact)

```
Show me the final call graph in two versions — Production and Tests — so the shape is identical and the only thing that changes is the injected layers/adapters (real vs in-memory).
```

### P4 — Targeted Review Loop (Revise, Don't Rewrite)

```
On "<snippet/line X>": <concrete change>.
Apply only this and re-emit the affected section — don't rewrite everything.
```

### P5 — Consolidate into a Spec

```
Consolidate everything we agreed on into a single, complete tech spec.
```

### P6 — Refine the Ubiquitous Language

```
What would be a better name for <concept>? → Use <NewName> and re-emit the full spec with that rename applied throughout.
```

### P7 — Encode a Cross-Cutting Convention (and Persist It)

```
Rule: don't use <antipattern> in <context>; instead <correct pattern>.
Encode this in AGENTS.md if it isn't already. Then re-emit the spec with that change.
```

### P8 — Hand Off to Implementation

```
Implement the spec at @<spec-path> using red-green-refactor TDD.
Start by bootstrapping <foundation>. Hard constraints: no <X>, no <Y>, no <Z>.
When you're done, tell me what's left in ≤5 todos.
```

## Integration with ControlKeel

### Pre-Planning Validation

Use `ck_validate` with the structural plan content:

```elixir
ck_validate(
  content: structural_plan,
  source_type: "developer",
  artifact_type: "source",
  kind: "code",
  intended_use: "plan"
)
```

### Governance Gates

Before implementation:
1. Submit structural plan via `ck_review_submit` (review_type: "plan")
2. Wait for approval
3. Only then proceed to implementation (P8)

### Boundary Enforcement

Use call graphs to enforce architectural boundaries:

- **Invalid cross-boundary calls**: Flag as `ck_finding` with category "architecture"
- **Missing seams**: Require dependency injection at boundaries
- **Adapter mismatch**: Ensure test adapters mirror production shape

### Invariant Enforcement

From the "Building Pi With Pi" principles:
- Prefer enforcing invariants (valid types, clear boundaries) over local workarounds
- Call graphs make violations visible before implementation
- Structural planning prevents "guessing at architecture" during coding

## Examples

### Example 1: Payment Service Structural Plan

**Type API:**
```typescript
interface PaymentService {
  charge(amount: number, method: PaymentMethod): Promise<PaymentResult>
  refund(paymentId: string): Promise<RefundResult>
}
```

**Call Stack:**
```
POST /api/payments/charge
  → PaymentController.charge()
    → PaymentService.charge()
      → StripeAdapter.charge()
      → Database.recordTransaction()
      → EventPublisher.publish()
```

**Seams:**
```typescript
interface PaymentGateway {
  charge(amount: number, method: PaymentMethod): Promise<PaymentResult>
}
interface TransactionStore {
  record(transaction: Transaction): Promise<void>
}
interface EventPublisher {
  publish(event: PaymentEvent): Promise<void>
}
```

**Adapters:**
- Production: `StripePaymentGateway`, `PostgresTransactionStore`, `KafkaEventPublisher`
- Test: `MockPaymentGateway`, `InMemoryTransactionStore`, `InMemoryEventPublisher`

### Example 2: Auth Module Structural Plan

**Type API:**
```elixir
defmodule MyApp.Auth do
  @callback authenticate(credentials()) :: {:ok, user()} | {:error, reason()}
  @callback authorize(user(), resource()) :: :ok | {:error, reason()}
end
```

**Call Stack:**
```
POST /api/dashboard
  → DashboardPlug.call()
    → SessionPlug.ensure_authenticated()
      → MyApp.Auth.authenticate()
        → SessionStore.get()
        → UserRepo.find()
    → AuthorizationPlug.authorize()
      → MyApp.Auth.authorize()
        → PolicyChecker.check()
```

**Seams:**
```elixir
@callback SessionStore.get(session_id()) :: session() | nil
@callback UserRepo.find(user_id()) :: user() | nil
@callback PolicyChecker.check(user(), resource()) :: boolean()
```

**Adapters:**
- Production: `RedisSessionStore`, `PostgresUserRepo`, `RulePolicyChecker`
- Test: `MapSessionStore`, `InMemoryUserRepo`, `AllowAllPolicyChecker`

## Validation Patterns

### Call Graph Consistency

Validate that:
1. Production and test call graphs have identical shape
2. All cross-boundary calls go through defined seams
3. No direct dependencies on concrete implementations

```elixir
ck_validate(
  content: call_graph_definition,
  artifact_type: "source",
  kind: "code",
  domain_pack: "software"
)
# Flags: boundary violations, missing seams, adapter mismatches
```

### Type API Completeness

Validate that:
1. All public interfaces are defined
2. Type signatures are complete (no `any` types)
3. Error handling is explicit in type definitions

### Seam Coverage

Validate that:
1. All external dependencies are behind seams
2. Production and test adapters implement the same interface
3. No direct calls to external services without adapter layer

## Continuous Improvement

Track metrics:
- Time from structural plan to implementation
- Defect rate in structurally planned vs. ad-hoc features
- Revision count during planning phase (P4 targeted loops)
- Boundary violation rate in implementation

## Benefits

1. **Mental Alignment**: Humans and agents agree on architecture before coding
2. **Boundary Enforcement**: Call graphs make violations visible early
3. **Testability**: Identical production/test shapes enable easy testing
4. **Maintainability**: Structural plans serve as living documentation
5. **Reduced Rework**: Targeted review loops prevent wholesale rewrites

## Anti-Patterns to Avoid

### ❌ Prose-Heavy Plans

Bad:
```
We need to refactor the auth system to be more modular. The session management
should be separated from user authentication, and we should use dependency
injection for better testability.
```

Good:
```typescript
// Type API
interface AuthSystem {
  authenticate(credentials: Credentials): Promise<AuthResult>
  authorize(user: User, resource: Resource): Promise<AuthorizeResult>
}

// Call Stack with seams clearly defined
```

### ❌ Implementation-Detailed Plans

Bad:
```
Create a class called AuthService with a method authenticate() that takes
a username and password, hashes the password with bcrypt, queries the database...
```

Good:
```
// Type API
interface AuthService {
  authenticate(credentials: Credentials): Promise<AuthResult>
}
// Implementation details come later
```

### ❌ Missing Test Adapters

Bad:
Only production call graph shown

Good:
Both production and test call graphs with identical shape

## Integration with Existing CK Skills

- **align**: Use for initial goal alignment before structural planning
- **plan-slice**: Use structural plans as input for slice decomposition
- **controlkeel-governance**: Validate structural plans before implementation
- **agent-pattern-verification**: Validate implementation against structural plan

## References

- Dillon Mulroy's structural planning workflow
- Luis Sanchez's analysis of planning patterns
- Leo Tavares on call graphs as boundary information
- "Building Pi With Pi" on invariant enforcement