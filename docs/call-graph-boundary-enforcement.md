# Call Graph Boundary Enforcement

This guide outlines how to use call graphs to enforce architectural boundaries in AI-assisted development, based on Leo Tavares' insight that "call graphs tell agents what's allowed to talk to what."

## Core Insight

**Call graphs are boundary enforcement tools.**

As Leo Tavares noted: "Types tell the agent what exists, the call graph tells it what's allowed to talk to what. That's the boundary info models otherwise guess at and get wrong. You hand it the architecture instead of hoping it infers it."

## Why Call Graphs Matter

### The Problem with Inferred Architecture

Without explicit call graphs, AI models must guess at:
- Which modules can call which other modules
- Where architectural boundaries should be
- What dependencies are allowed vs. forbidden
- Where to inject seams and adapters

This leads to:
- Violated architectural constraints
- Tight coupling between unrelated components
- Difficulty testing individual modules
- Code that's hard to reason about

### The Solution: Explicit Call Graphs

Explicit call graphs provide:
- **Clear boundaries**: What can talk to what
- **Validation targets**: Checkable constraints
- **Documentation**: Living architecture documentation
- **Guidance**: Clear rules for implementation

## Call Graph Structure

### Basic Call Graph

```
Entrypoint → Module A → Module B → Module C
                    → Module D → Module E
```

### Annotated Call Graph

```
POST /api/auth/login
  → AuthController (boundary: web)
    → AuthService (boundary: domain)
      → UserRepository (boundary: infrastructure)
      → SessionStore (boundary: infrastructure)
```

### Bounded Call Graph

```
[Web Layer]
  AuthController
    ↓ (allowed)
[Domain Layer]
  AuthService
    ↓ (allowed)
[Infrastructure Layer]
  UserRepository
  SessionStore

✗ AuthController → UserRepository (forbidden: skips domain layer)
✗ AuthService → ExternalAPI (forbidden: domain can't call external directly)
```

## Boundary Types

### 1. Layer Boundaries

Enforce layered architecture:

```
[Presentation Layer]
  Controllers
    ↓ calls
[Domain Layer]
  Services
    ↓ calls
[Infrastructure Layer]
  Repositories
  External APIs
```

### 2. Domain Boundaries

Enforce domain separation:

```
[Auth Domain]
  AuthService
  SessionService
  
[User Domain]
  UserService
  ProfileService

✗ AuthService → UserService (forbidden: cross-domain direct call)
✓ AuthService → UserService via DomainEvent (allowed: async boundary)
```

### 3. Capability Boundaries

Enforce capability separation:

```
[Read Capability]
  QueryService
  ReadOnlyRepository

[Write Capability]
  CommandService
  WriteRepository

✗ QueryService → WriteRepository (forbidden: read can't write)
✓ CommandService → WriteRepository (allowed: write can write)
```

### 4. Seams and Adapters

Enforce dependency injection boundaries:

```
[Application]
  AuthService
    ↓ calls interface
[Seam]
  UserRepository (interface)
    ↓ implemented by
[Adapters]
  PostgresUserRepository (production)
  InMemoryUserRepository (test)
```

## Validation Patterns

### Pattern 1: Boundary Violation Detection

```elixir
def validate_call_graph(call_graph, boundaries) do
  violations = []
  
  call_graph.edges
  |> Enum.each(fn edge ->
    if violates_boundary?(edge, boundaries) do
      violations = [edge | violations]
    end
  end)
  
  %{valid: Enum.empty?(violations), violations: violations}
end
```

### Pattern 2: Layer Compliance

```elixir
ck_validate(
  content: call_graph_definition,
  artifact_type: "source",
  kind: "code",
  metadata: %{
    validation_rule: "layer_compliance",
    layers: ["web", "domain", "infrastructure"],
    allowed_transitions: [
      {"web", "domain"},
      {"domain", "infrastructure"}
    ],
    forbidden_transitions: [
      {"web", "infrastructure"},
      {"infrastructure", "domain"}
    ]
  }
)
```

### Pattern 3: Seam Enforcement

```elixir
ck_validate(
  content: implementation_code,
  artifact_type: "source",
  kind: "code",
  metadata: %{
    validation_rule: "seam_enforcement",
    require_interfaces: true,
    forbid_concrete_dependencies: ["Postgres", "Redis", "HTTP"]
  }
)
```

## ControlKeel Integration

### Pre-Implementation Validation

Validate call graphs before implementation:

```elixir
# Validate the structural plan's call graph
validation_result = ck_validate(
  content: structural_plan,
  source_type: "developer",
  artifact_type: "source",
  kind: "code",
  metadata: %{
    validation_phase: "planning",
    check_boundaries: true
  }
)

if validation_result.decision == "block" do
  # Record boundary violations
  Enum.each(validation_result.findings, fn finding ->
    ck_finding(
      category: "architecture",
      severity: "high",
      rule_id: "CK-BOUNDARY-001",
      plain_message: "Call graph boundary violation: #{finding.description}",
      decision: "block"
    )
  end)
end
```

### Implementation Validation

Validate implementation against call graph:

```elixir
# Validate that implementation matches planned call graph
validation_result = ck_validate(
  content: implementation_code,
  source_type: "generated",
  artifact_type: "diff",
  kind: "code",
  metadata: %{
    validation_phase: "implementation",
    expected_call_graph: planned_call_graph,
    allow_violations: false
  }
)
```

### Continuous Validation

Validate during ongoing development:

```elixir
# In CI/CD pipeline
def validate_boundaries do
  call_graph = extract_call_graph()
  
  validation_result = ck_validate(
    content: call_graph,
    artifact_type: "source",
    kind: "code",
    metadata: %{
      validation_rule: "continuous_boundary_check",
      project_boundaries: load_project_boundaries()
    }
  )
  
  if validation_result.decision == "block" do
    raise "Boundary violations detected: #{inspect(validation_result.findings)}"
  end
end
```

## Boundary Definition

### Project Boundary File

Create `docs/architectural-boundaries.md`:

```markdown
# Architectural Boundaries

## Layer Boundaries

- **Web Layer**: Controllers, plugs, routes
  - Allowed to call: Domain Layer
  - Forbidden to call: Infrastructure Layer directly

- **Domain Layer**: Services, business logic
  - Allowed to call: Infrastructure Layer through interfaces
  - Forbidden to call: Web Layer

- **Infrastructure Layer**: Repositories, external APIs
  - Allowed to call: External services, databases
  - Forbidden to call: Domain or Web Layers

## Domain Boundaries

- **Auth Domain**: Authentication, sessions
  - Forbidden to call: User Domain directly
  - Allowed: Domain events for cross-domain communication

- **User Domain**: User management, profiles
  - Forbidden to call: Auth Domain directly
  - Allowed: Domain events for cross-domain communication

## Seam Requirements

All external dependencies must be behind interfaces:
- Databases → Repository interfaces
- External APIs → Service interfaces
- Caching → Cache interfaces

## Forbidden Patterns

- Direct database access from web layer
- Direct HTTP calls from domain layer
- Concrete dependencies in domain layer
- Circular dependencies between modules
```

### ControlKeel Boundary Configuration

```json
{
  "boundaries": {
    "layers": {
      "web": {
        "allowed_calls": ["domain"],
        "forbidden_calls": ["infrastructure", "external"]
      },
      "domain": {
        "allowed_calls": ["infrastructure"],
        "forbidden_calls": ["web", "external"]
      },
      "infrastructure": {
        "allowed_calls": ["external", "database"],
        "forbidden_calls": ["web", "domain"]
      }
    },
    "seams": {
      "database": ["Repository"],
      "cache": ["Cache"],
      "external_api": ["Service"]
    }
  }
}
```

## Examples

### Example 1: Layer Boundary Violation

**Call Graph:**
```
AuthController → PostgresUserRepository
```

**Validation:**
```elixir
ck_validate(
  content: call_graph,
  metadata: %{
    validation_rule: "layer_compliance",
    violation: "web → infrastructure direct call"
  }
)
# Returns: BLOCKED - Web layer cannot call infrastructure directly
```

**Correction:**
```
AuthController → UserService → UserRepository (interface) → PostgresUserRepository
```

### Example 2: Seam Violation

**Code:**
```elixir
defmodule AuthService do
  def authenticate(credentials) do
    # Direct database call - no seam
    user = PostgresRepo.query("SELECT * FROM users WHERE email = ?", [credentials.email])
  end
end
```

**Validation:**
```elixir
ck_validate(
  content: code,
  metadata: %{
    validation_rule: "seam_enforcement",
    violation: "direct concrete dependency in domain layer"
  }
)
# Returns: BLOCKED - Domain layer cannot have concrete dependencies
```

**Correction:**
```elixir
defmodule AuthService do
  def authenticate(credentials) do
    # Interface-based dependency
    user = @user_repo.find_by_email(credentials.email)
  end
end
```

### Example 3: Domain Boundary Violation

**Call Graph:**
```
AuthService → UserService
```

**Validation:**
```elixir
ck_validate(
  content: call_graph,
  metadata: %{
    validation_rule: "domain_separation",
    violation: "direct cross-domain call"
  }
)
# Returns: BLOCKED - Auth domain cannot call User domain directly
```

**Correction:**
```
AuthService → UserAuthenticatedEvent → EventBus → UserService
```

## Advanced Patterns

### Pattern: Dynamic Boundary Detection

Automatically detect boundaries from code structure:

```elixir
def detect_boundaries(codebase) do
  modules = extract_modules(codebase)
  dependencies = extract_dependencies(codebase)
  
  layers = infer_layers(modules, dependencies)
  seams = detect_seams(modules, dependencies)
  
  %{layers: layers, seams: seams}
end
```

### Pattern: Boundary Evolution Tracking

Track how boundaries change over time:

```elixir
def track_boundary_evolution(old_graph, new_graph) do
  added_violations = find_new_violations(old_graph, new_graph)
  removed_violations = find_removed_violations(old_graph, new_graph)
  
  ck_finding(
    category: "architecture",
    severity: "medium",
    rule_id: "CK-BOUNDARY-EVOLUTION-001",
    plain_message: "Boundary changes: #{inspect(added_violations)} added, #{inspect(removed_violations)} removed",
    metadata: %{
      added: added_violations,
      removed: removed_violations
    }
  )
end
```

### Pattern: Test Call Graph Validation

Ensure test call graphs mirror production:

```elixir
def validate_test_call_graph(prod_graph, test_graph) do
  # Structure should be identical, only adapters change
  structure_diff = compare_structure(prod_graph, test_graph)
  
  if structure_diff != [] do
    ck_finding(
      category: "testing",
      severity: "medium",
      rule_id: "CK-TEST-BOUNDARY-001",
      plain_message: "Test call graph structure differs from production: #{inspect(structure_diff)}"
    )
  end
end
```

## Integration with Other Patterns

### With Structural Planning

Use call graphs as part of structural artifacts:

1. Define call graph in structural plan
2. Validate boundaries during planning
3. Enforce boundaries during implementation
4. Continuously validate in CI/CD

### With Invariant Enforcement

Call graphs are architectural invariants:

1. Define boundaries as invariants
2. Use CK-INVARIANT-001 for boundary violations
3. Enforce at planning, implementation, and runtime
4. Record violations as findings

### With Self-Correction Loops

Use boundary validation in agentic loops:

1. Generate implementation
2. Validate against call graph boundaries
3. Feed violations back to agent
4. Correct and re-validate
5. Repeat until valid

## Best Practices

1. **Define Boundaries Early**: Specify boundaries before implementation
2. **Make Boundaries Explicit**: Document in boundary files and call graphs
3. **Validate Continuously**: Check boundaries at each phase
4. **Enforce Automatically**: Use CI/CD to prevent violations
5. **Evolve Intentionally**: Change boundaries only with explicit decisions
6. **Monitor Violations**: Track patterns of violations over time

## Metrics and Monitoring

Track boundary health:
- **Violation Rate**: % of changes that violate boundaries
- **Correction Time**: Time to fix boundary violations
- **Boundary Stability**: How often boundaries change
- **Seam Coverage**: % of external dependencies behind seams
- **Layer Adherence**: % of code that follows layer rules

## References

- Leo Tavares on call graphs as boundary information
- Structural planning guide for call graph artifacts
- ControlKeel governance and validation patterns
- Invariant enforcement guidance