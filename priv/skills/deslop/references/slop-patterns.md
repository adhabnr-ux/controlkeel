# Slop Pattern Catalog

Common AI-generated code patterns that should be removed during deslop. Each
pattern includes what to look for and the subtraction rule.

## Issue and PR Text Patterns

### Over-confident root cause analysis without evidence
```markdown
# Bad: confident diagnosis without supporting evidence
The issue is clearly caused by a race condition in the user session manager. We should add a mutex lock around the session state mutations to prevent concurrent access.

# Good: stick to observed facts
When two requests hit the session endpoint simultaneously, I see session state corruption in the logs. Here's the exact error and reproduction steps.
```

### Generic implementation strategies
```markdown
# Bad: generic advice without project-specific context
The best approach would be to implement a comprehensive retry mechanism with exponential backoff, circuit breaker pattern, and extensive monitoring.

# Good: specific, actionable guidance tied to the actual problem
Add retry with exponential backoff (max 3 attempts) to the `ApiClient.post/2` function, which currently fails on network timeouts.
```

### Long lists of irrelevant error classes
```markdown
# Bad: enumerating possible issues without narrowing down
This could be caused by: network timeouts, SSL certificate errors, DNS resolution failures, malformed JSON responses, rate limiting, authentication failures, or server-side bugs.

# Good: specific error with context
The specific error is `{:error, :timeout}` after 30 seconds when calling the external payment API. Here's the full stack trace.
```

### AI-generated issue expansion
```markdown
# Bad: expands narrow observation into broad hypotheses
The login button doesn't work. This suggests potential problems with the authentication flow, session management, CSRF token validation, user database integrity, or frontend event handling. We should audit the entire auth subsystem.

# Good: focused on the actual observation
Clicking the login button does nothing. No network request is sent to `/auth/login` and no error appears in the console. Here are the browser devtools screenshots.
```

### Hallucinated code references
```markdown
# Bad: confident but wrong code references
The bug is in `lib/my_app/auth/session_manager.ex` line 45 where the `validate_session/1` function doesn't check for expired tokens.

# Good: accurate code references after actual investigation
The issue is in `lib/my_app/web/auth_plug.ex` where the `call/2` function doesn't validate session expiration before proceeding.
```

## Comments

### Narrative comments
```elixir
# Bad: describes what the code does
# Check if the user is authenticated before proceeding
if user do
  ...
end

# Good: delete the comment, the code is self-explanatory
if user do
  ...
end
```

### Story comments
```elixir
# Bad: tells a story
# First, we need to get the user from the database.
# Then, we check if they have admin privileges.
# If they do, we allow access to the dashboard.
user = Accounts.get_user!(id)
if Accounts.admin?(user), do: render_dashboard(user)

# Good: just the code
user = Accounts.get_user!(id)
if Accounts.admin?(user), do: render_dashboard(user)
```

### Kept comments
```elixir
# Keep: explains WHY, not what
# Using pessimistic locking here because concurrent updates
# caused a race condition in production (see #1234)
Repo.lock(user)
```

## Verbosity

### Unnecessary intermediate variables
```elixir
# Bad
result = do_something()
final_result = process(result)
return_value = format(final_result)
return_value

# Good
do_something() |> process() |> format()
```

### Overly explicit pattern matching
```elixir
# Bad
case value do
  true -> handle_true()
  false -> handle_false()
end

# Good
if value, do: handle_true(), else: handle_false()
```

## Dead Code

### Unused imports
```elixir
# Bad: imported but never referenced
alias MyApp.SomeModule  # never used

# Good: delete the import
```

### TODO stubs with no implementation
```elixir
# Bad
def handle_error(error) do
  # TODO: implement error handling
  :ok
end

# Good: implement it or remove the function if not called
```

### Unreachable branches
```elixir
# Bad: else branch can never execute
if true do
  do_thing()
else
  handle_impossible_case()  # dead code
end

# Good: remove the conditional entirely
do_thing()
```

## Padding

### Single-call wrappers
```elixir
# Bad: helper adds no logic, just redirects
def get_user_name(user), do: user.name

# Good: just call user.name directly at the call site
```

### Generic error messages
```elixir
# Bad
{:error, "An error occurred while processing the request"}

# Good
{:error, "Payment gateway timeout: #{status} after #{timeout}ms"}
```

## Hallucinated Patterns

### Imports for non-existent modules
```elixir
# Bad: module does not exist in the project
alias Phoenix.HTML.Form  # wrong module name

# Good: use the actual module
alias Phoenix.Component
```

### Redundant type specs
```elixir
# Bad: typespec repeats what the function body already makes clear
@spec add(integer(), integer()) :: integer()
def add(a, b), do: a + b

# Good: keep typespecs for public APIs, remove for trivial private functions
```
