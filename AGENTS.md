This is a web application written using the Phoenix web framework.

## ⚠️ CRITICAL: ControlKeel Governance Requirements (ALL HOSTS)

This project is governed by ControlKeel. **ALL hosts must follow these governance protocols** before making any changes:

### Mandatory First Steps for EVERY Session (No Exceptions)

1. **Call ck_context** - Load mission, budget, findings, proof, workspace context
   - Required at session start, even when resuming from conversation summaries
   - Conversation summaries are NOT substitutes for governed state

2. **Invoke controlkeel-governance skill** - Activate governance framework
   - Required before any code edits, shell execution, or implementation work
   - Works across all hosts (Claude Code, Cursor, OpenCode, etc.)

3. **Check budget** - Call ck_budget before expensive work
   - Required for multi-phase implementations or expensive operations

4. **Validate before writing** - Call ck_validate before code/config/shell/deploy
   - Required for ALL code changes, configuration updates, shell commands
   - Pass appropriate domain_pack (e.g., security, hipaa) and capabilities

5. **Record decisions** - Use ck_memory_record for important decisions
   - Required for architecture decisions, assumptions, operator guidance

6. **Record findings** - Use ck_finding for any issues discovered
   - Required for security issues, compliance violations, governance gaps

### Session Resumption Protocol

When resuming work from a conversation summary or previous session:

❌ **DO NOT** treat it as continuation without governance
✅ **DO** invoke fresh governance protocols (ck_context + controlkeel-governance skill)

**Rule**: Every session is a new session from a governance perspective.

### Host-Specific Notes

- **Claude Code**: Use MCP tools (ck_context, ck_validate, etc.)
- **Cursor**: Use MCP tools (ck_context, ck_validate, etc.)
- **OpenCode**: Use MCP tools (ck_context, ck_validate, etc.)
- **Devin Terminal**: Use MCP tools (ck_context, ck_validate, etc.)
- **Any other host**: Use MCP tools if available, otherwise follow manual checklist

### Manual Governance Checklist (If MCP Unavailable)

If MCP tools are unavailable, you MUST complete this checklist before making changes:

- [ ] Check if session is critical-risk (HIPAA, HITECH, OWASP compliance)
- [ ] Review active findings in the project (check CK dashboard or prior session notes)
- [ ] Check budget before starting work
- [ ] Validate all code changes manually against security best practices
- [ ] Document all decisions in a session notes file

### Enforcement Mechanisms

1. **CLAUDE.md / AGENTS.md**: This file — read at session start by all hosts
2. **ck_context**: Primary governance state check via MCP

## Context File Scope

Keep this root `AGENTS.md` lean: project-specific governance, critical gotchas,
framework rules, and commands only. Reusable agent guidance belongs in skills or
focused docs so every session does not carry unnecessary context.

For CLAUDE.md/AGENTS.md maintenance, large-codebase setup, hierarchical context
files, scoped commands, codebase maps, LSP setup, and organizational adoption
patterns, see [docs/large-codebase-patterns.md](docs/large-codebase-patterns.md).

### Consequences of Governance Violations

- Critical-risk sessions: Immediate escalation, potential rollback
- Non-critical sessions: Warning, retrospective required
- Repeated violations: Access restrictions, mandatory training

**Remember**: In governed sessions, governance protocols are NOT optional workflow steps - they are essential safety rails.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- In OpenCode, use the provided `apply_patch` tool for manual file edits when it is available. Do not claim file editing is unavailable just because tools named `Edit` or `Write` are absent; bash remains disallowed for file writes.

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Use `Enum.at/2` for list index access (lists don't support `mylist[i]` syntax)
- Rebind block expressions: `socket = if connected?(socket), do: assign(socket, :val, val)` (never rebind inside blocks)
- Never nest multiple modules in same file (cyclic dependency risk)
- Use struct field access (`my_struct.field`) not map access syntax on structs
- Use stdlib `Time`, `Date`, `DateTime` for date/time (no extra deps except `date_time_parser` for parsing)
- Never use `String.to_atom/1` on user input (memory leak)
- Predicate functions end with `?`, reserve `is_` prefix for guards
- OTP primitives require names in child spec: `{DynamicSupervisor, name: MyApp.Sup}`
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure (typically `timeout: :infinity`)

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Router `scope` includes alias prefix (never add extra alias for routes)
- `Phoenix.View` is removed in Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- Always preload associations accessed in templates
- Import `Ecto.Query` in `seeds.exs`
- Schema fields use `:string` type even for text columns
- `validate_number/2` doesn't support `:allow_nil` option
- Use `Ecto.Changeset.get_field/2` to access changeset fields
- Programmatically set fields (e.g., `user_id`) must not be in `cast` calls (set explicitly)
- Use `mix ecto.gen.migration` with underscore names for correct conventions
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Use `~H` or .html.heex files, never `~E`
- Use `Phoenix.Component.form/1` and `inputs_for/1`, not `Phoenix.HTML.form_for`
- Use `to_form/2` for forms: `assign(socket, form: to_form(...))` and `<.form for={@form}>`
- Add unique DOM IDs to key elements for testability
- Import app-wide helpers in `my_app_web.ex` `html_helpers` block
- Use `cond` or `case` for multiple conditionals (no `else if` in Elixir)
- Use `phx-no-curly-interpolation` for literal `{}` in `<code>/<pre>` blocks
- Class attrs use list syntax: `class={["px-2", @flag && "py-5"]}` (wrap `if` in parens)
- Use `<%= for %>` for template content, never `<% Enum.each %>`
- Use `<%!-- comment --%>` for HEEx comments
- Interpolation: use `{...}` for attrs/values, `<%= %>` only for block constructs in tag bodies
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- Use `<.link navigate={href}>` and `<.link patch={href}>`, not deprecated `live_redirect`/`live_patch`
- Avoid LiveComponents unless specifically needed
- Name LiveViews with `Live` suffix: `AppWeb.WeatherLive` (router scope already aliased)

### LiveView streams

- Always use streams for collections to avoid memory bloat: `stream(socket, :messages, [msg])`
- Stream operations: append, `reset: true` for filtering, `at: -1` for prepend, `stream_delete/3` for removal

- Template: set `phx-update="stream"` on parent with DOM id, consume `@streams.name` with item ids

- Streams not enumerable (no `Enum.filter/2`). Refetch and re-stream with `reset: true` for filtering

- Track count/empty state via separate assigns (use Tailwind `hidden only:block` for empty states)

- Re-stream items when updating assigns that change streamed item content
- Never use deprecated `phx-update="append"` or `phx-update="prepend"`

### LiveView JavaScript interop

- Use `phx-update="ignore"` when `phx-hook` manages its own DOM
- Always provide unique DOM id with `phx-hook`
- Two hook types: colocated (`:type={Phoenix.LiveView.ColocatedHook}`) and external (passed to LiveSocket)
- Never use raw `<script>` tags in HEEx (use colocated hooks)
- Colocated hooks auto-integrated into app.js, names must start with `.`
- External hooks in `assets/js/`, passed to LiveSocket constructor
- Use `push_event/3` for server→client events (rebind socket: `socket = push_event(socket, "event", %{})`)
- Client hooks handle events with `this.handleEvent("event", callback)`
- Client→server: `this.pushEvent("event", data, replyCallback)`, server responds with `{:reply, data, socket}`

### LiveView tests

- Use `Phoenix.LiveViewTest` and `LazyHTML` for assertions
- Form tests: `render_submit/2` and `render_change/2`
- Reference element IDs from templates in tests (`element/2`, `has_element/2`)
- Test element presence, not raw HTML or text content
- Focus on outcomes, not implementation details
- Test against actual HTML structure, not expectations (use `LazyHTML` selectors for debug)

### Form handling

#### Creating a form from params

- From params: `assign(socket, form: to_form(params))` 
- For nesting: `to_form(user_params, as: :user)`

#### Creating a form from changesets

- From changesets: `to_form(changeset)` auto-computes `:as` option

    

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

- Always use `to_form/2` assigns in LiveView, never access changesets directly in templates
- Use `<.form for={@form} ...>` with `@form[:field]` references, never `<.form let={f} ...>`
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->

<!-- controlkeel:start -->
# ControlKeel Companion Instructions

This project is governed by ControlKeel. Prefer the ControlKeel MCP server for validation, findings, budgets, proof context, workspace snapshots, transcript state, and routing.

Project root: this repository (your IDE workspace / `CK_PROJECT_ROOT`)
Target: `opencode`
Primary CK loop: `ck_context -> ck_validate -> ck_review_submit/ck_finding -> ck_budget/ck_route/ck_delegate`

Required workflow:
1. Call `ck_context` at the start of a task for mission, workspace, transcript, and resume context.
2. Call `ck_validate` before writing code, config, shell, or deploy content.
3. Submit plans or approval packets with `ck_review_submit` and check `ck_review_status` before execution.
4. Record any human-review issue with `ck_finding`.
5. Check `ck_budget` before expensive model or multi-agent work, and keep `ck_context` compact unless full raw context is needed.
6. Before AFK or delegated implementation, split large work into human-approved vertical slices with explicit dependencies; prefer durable behavior-first issues, stable deep-module interfaces, and branch-level automated review plus human QA before merge.
7. Use `ck_route`, `ck_skill_list`, and `ck_skill_load` to delegate or activate specialized CK workflows.

Install ControlKeel:
- Homebrew: `brew tap aryaminus/controlkeel && brew install controlkeel`
- npm bootstrap: `npm i -g @aryaminus/controlkeel`
- Unix installer: `curl -fsSL https://github.com/aryaminus/controlkeel/releases/latest/download/install.sh | sh`
- Raw GitHub shell installer: `curl -fsSL https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.sh | sh`
- PowerShell installer: `irm https://github.com/aryaminus/controlkeel/releases/latest/download/install.ps1 | iex`
- Raw GitHub PowerShell installer: `irm https://raw.githubusercontent.com/aryaminus/controlkeel/main/scripts/install.ps1 | iex`
- GitHub Releases: `https://github.com/aryaminus/controlkeel/releases`

ControlKeel auto-bootstraps project binding on first use. Provider access resolves through agent bridge, CK-owned provider profiles, local Ollama, then heuristic fallback.
<!-- controlkeel:end -->
