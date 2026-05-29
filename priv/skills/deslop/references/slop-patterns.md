# Slop Pattern Catalog

Common AI-generated code patterns that should be removed during deslop. Each
pattern includes what to look for and the subtraction rule.

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
