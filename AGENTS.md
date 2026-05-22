This is a Phoenix web application governed by ControlKeel.

## ControlKeel Governance

Before shell, code, config, deploy, or broad cleanup work:

1. Call `ck_context` for mission, budget, findings, proof, workspace, and resume state.
2. Invoke the `controlkeel-governance` skill.
3. Call `ck_budget` before expensive, multi-phase, or delegated work.
4. Call `ck_validate` before shell commands, file writes, generated code, config changes, or deploy actions.
5. Use `ck_review_submit` and wait for `ck_review_status` approval before broad mutations or risky deletion.
6. Record durable decisions with `ck_memory_record`.
7. Record discovered issues with `ck_finding`.
8. Use `ck_route` before delegation.

Fresh sessions must reacquire CK state even if a conversation summary exists. If MCP is unavailable, manually check risk, findings, budget, and security implications before changing files, then leave clear session notes.

Keep this root file lean: only project-specific governance, commands, and critical gotchas belong here. Put reusable agent guidance in skills or focused docs. For large-codebase setup, AGENTS/CLAUDE maintenance, scoped commands, maps, hooks, and LSP patterns, see `docs/large-codebase-patterns.md`. For token cleanup, see `docs/TOKEN_OPTIMIZATION_GUIDE.md`.

## Project Commands

- Run `mix precommit` after code changes and fix pending issues.
- Use `Req` for HTTP; avoid `:httpoison`, `:tesla`, and `:httpc`.
- Use `apply_patch` for manual edits when available. Do not use shell writes for file edits.
- Read `mix help <task>` before unfamiliar Mix tasks.
- Prefer targeted tests first: `mix test test/path/to_test.exs` or `mix test --failed`.
- Avoid `mix deps.clean --all` unless there is a specific dependency corruption reason.

## Phoenix v1.8

- LiveView templates must start with `<Layouts.app flash={@flash} ...>` and pass `current_scope` when required.
- `Layouts` is already aliased through `my_app_web.ex`; do not add redundant aliases.
- Fix missing `current_scope` by moving routes into the right `live_session` and passing the assign through layout boundaries.
- `<.flash_group>` belongs only in `layouts.ex`.
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>`; do not call Heroicons modules directly.
- Use imported `<.input>` for form inputs. If overriding `class`, fully style the input because defaults are not inherited.
- Router scopes already include aliases; do not add duplicate route aliases.
- Do not use `Phoenix.View`.

## Elixir and Ecto

- Use `Enum.at/2` for list index access.
- Rebind block results outside the block.
- Do not nest multiple modules in one file.
- Access struct fields with `struct.field`, not map syntax.
- Use stdlib `Time`, `Date`, and `DateTime`; only use extra parsing deps already in the project.
- Never use `String.to_atom/1` on user input.
- Predicate functions end in `?`; reserve `is_` names for guards.
- Name OTP child specs, for example `{DynamicSupervisor, name: MyApp.Sup}`.
- Use `Task.async_stream/3` with back-pressure for concurrent enumeration.
- Preload associations used in templates.
- Use `:string` for schema text fields.
- `validate_number/2` has no `:allow_nil` option.
- Use `Ecto.Changeset.get_field/2` for changeset fields.
- Set programmatic fields like `user_id` explicitly, not through `cast`.
- Create migrations with `mix ecto.gen.migration descriptive_name`.

## HEEx and LiveView

- Use `~H` and `.html.heex`, never `~E`.
- Use `Phoenix.Component.form/1`, `inputs_for/1`, and `to_form/2`; do not use `Phoenix.HTML.form_for` or `<.form let={f}>`.
- Give every form a unique DOM id.
- Import app-wide helpers through the `html_helpers` block.
- Use `cond` or `case`; Elixir has no `else if`.
- Use `phx-no-curly-interpolation` for literal braces in `<code>` and `<pre>`.
- Use list syntax for class attrs and wrap inline `if` expressions.
- Use `<%= for %>` for template loops, not `Enum.each`.
- Use `<%!-- comment --%>` for HEEx comments.
- Use `{...}` for attributes and values; use `<%= %>` only for block constructs in tag bodies.
- Prefer `<.link navigate={href}>` and `<.link patch={href}>` over deprecated LiveView redirects.
- Avoid LiveComponents unless they solve a real boundary.
- Name LiveViews with a `Live` suffix.

## Streams, Hooks, and Tests

- Use LiveView streams for collections. Set `phx-update="stream"`, consume `@streams.name`, and use `reset: true` for filtering.
- Streams are not enumerable; refetch and re-stream instead of filtering in memory.
- Track counts and empty states in separate assigns.
- Re-stream items when assigns affecting streamed content change.
- Do not use deprecated `phx-update="append"` or `prepend`.
- Use `phx-update="ignore"` when a hook owns its DOM, and always provide a unique hook id.
- Prefer colocated hooks for template-local JS; keep ad hoc JavaScript out of HEEx templates.
- Use `push_event/3` for server-to-client events and rebind the socket.
- Use `Phoenix.LiveViewTest` and LazyHTML assertions. Test outcomes and selectors, not raw HTML blobs.
- In tests, use `start_supervised!/1`. Avoid `Process.sleep/1` and `Process.alive?/1`; use monitors or `_ = :sys.get_state(pid)` for synchronization.

## JS, CSS, and UI

- Tailwind v4 import syntax in `app.css` must stay:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- Do not use `@apply` in raw CSS.
- Build custom Tailwind components; do not add daisyUI.
- Only `app.js` and `app.css` bundles are supported. Import vendor deps there; do not reference external scripts/styles from layouts.
- Keep UI polished, responsive, accessible, and restrained. Use subtle transitions, clean spacing, and balanced typography.
