# Branch Split Plan — Framework Layouts + Local Auth (3 phases)

**Reference branch:** `refactor/framework-layout` (read-only reference; do not ship from it)
**Target:** re-do the work as **three stacked branches** off `main`, each reviewable and shippable on its own.

This doc plans the 3-way split. Each phase is self-contained — it compiles and
renders correctly in isolation — and each builds on the previous.

---

## Why split into three

The reference branch is one large diff (~57 files, ~7.5k lines) bundling three
distinct concerns. Splitting by **kind of change** gives each branch a single
review story:

1. **New / changed (substantive)** — the new `Layouts` module, templates, helpers,
   and the wiring that is safe to land first (the **public** side, which is
   self-contained).
2. **Delete + mechanical** — wire the dashboard/observability framework layouts,
   remove the ~37 LV wrappers, delete the 5 legacy layout modules.
3. **Local-auth-toggle** — `CONTROLKEEL_FORCE_AUTH` + header UX (behavior).

### Critical ordering constraint
A `live_session` can hold **one** framework layout. If you wire `:dashboard`
to a framework layout while the LVs still render `<DashboardLayout.dashboard …>`
inside, you get **double chrome**. Therefore the dashboard/observability
**wiring must land in the same phase as the wrapper removal** (Phase 2). Phase 1
creates those templates but deliberately does **not** wire them yet — so
dashboard/observability keep rendering through the (still-present) function
component layouts.

---

## Branch topology

```
main
 └─ phase1: refactor/framework-layouts-core       (new module/templates + public migration)
     └─ phase2: refactor/framework-layouts-cleanup (wire dashboard/obs + remove wrappers + delete legacy)
         └─ phase3: feat/local-auth-toggle          (force-auth + header UX)
```

---

## How to use the reference branch

The reference branch evolved iteratively (function-component layouts → framework
layouts). **Do not replicate its intermediate commits.** Target each phase's end
state and reach it directly:

```bash
# Phase 2 end state (the full migration, before auth):
git diff main 0744ed0 -- <path>

# Phase 3 (the auth commit, in isolation):
git show 7da4fae -- <path>
```

| Ref commit | Maps to | What |
|---|---|---|
| `c5b1c06` … `cce3534` | (iterative) | intermediate steps — ignore |
| `0744ed0` | **Phase 1 + Phase 2 combined end state** | framework layouts + removed modules |
| `7da4fae` | **Phase 3** | auth enforcement flag + header UX |

> ⚠️ **Phase 1 has no exact commit on the reference branch.** The ref branch
> wired everything at once. When building Phase 1, cherry-pick the *files* from
> `0744ed0` but **defer the dashboard/observability live_session wiring to
> Phase 2** (see the constraint above).

---

# Phase 1 — `refactor/framework-layouts-core`

**Base:** `main`
**Goal:** create the `Layouts` module, all framework-layout templates, and
helpers; migrate the **self-contained public side** (`/`, `/getting-started`).
Leave dashboard/observability rendering exactly as today (function-component
layouts), so nothing breaks.
**Reference files:** from `0744ed0`.

## Scope

### New files
- `lib/controlkeel_web/components/layouts.ex` — module: `embed_templates "layouts/*"` + `sidebar/1`, `flash_group/1`, and private helpers (`nav_link_class/2`, `tab_class/2`, `tab_inactive_class/0`, `tab_base_class/0`). (`sidebar`/helpers are unused until Phase 2 — that's expected.)
- `lib/controlkeel_web/components/layouts/root.html.heex` — moved from `root_layout.ex`.
- `lib/controlkeel_web/components/layouts/public.html.heex` — from `public_layout.ex` (`{@inner_content}`, reads `@current_user`/`@flash`). **Use the baseline version** (Dashboard link + always-on Sign in/up); the conditional UI is Phase 3.
- `lib/controlkeel_web/components/layouts/dashboard.html.heex` — created now, **not wired until Phase 2**.
- `lib/controlkeel_web/components/layouts/observability.html.heex` — created now, **not wired until Phase 2**.
- `lib/controlkeel_web/components/layouts/observability_session.html.heex` — created now, **not wired until Phase 2**.
- `lib/controlkeel_web/live/nav_highlight.ex` — created now, **not wired until Phase 2**.

### Changed files
- `lib/controlkeel_web.ex` — `alias ControlKeelWeb.RootLayout` → `Layouts`; add `layouts: [html: ControlKeelWeb.Layouts]` to the `:controller` macro; remove the `PublicLayout` alias.
- `lib/controlkeel_web/router.ex` — **only** the two `put_root_layout {ControlKeelWeb.RootLayout, :root}` → `{ControlKeelWeb.Layouts, :root}` (browser + saml_acs pipelines). **Do NOT touch the `:cloud_auth`/observability live_sessions yet.**
- `lib/controlkeel_web/controllers/page_controller.ex` — `plug :put_layout, html: {ControlKeelWeb.Layouts, :public}`.
- `lib/controlkeel_web/controllers/page_html/home.html.heex` — drop `<PublicLayout.public>` wrapper.
- `lib/controlkeel_web/controllers/page_html/getting_started.html.heex` — drop `<PublicLayout.public>` wrapper.

### Deleted
- `components/root_layout.ex` (folded into `layouts.ex`).
- `components/public_layout.ex` (folded into `layouts/public.html.heex`).

### Untouched (intentional — deferred to Phase 2)
`dashboard_layout.ex`, `observability_layout.ex`, `observability_session_layout.ex`, and **all ~37 LiveViews**. They keep rendering via the function-component layouts.

## Steps
1. Create `layouts.ex` (module + function components + helpers) and the 5 `layouts/*.html.heex` templates; create `nav_highlight.ex`.
2. Rename `RootLayout`→`Layouts` (module + 2× `put_root_layout`); fold `root_layout.ex` into `layouts.ex`.
3. Wire the public side: `PageController` `put_layout`, controller-macro `layouts:` config; strip wrappers from `home`/`getting_started`; fold `public_layout.ex` into `layouts/public.html.heex`; remove aliases.
4. `mix precommit`; smoke-test `/` and `/getting-started`.

## Verification
- `mix precommit` green (the `bin_wrapper` stdout-noise failure is environmental).
- `/` and `/getting-started` render inside the `:public` framework layout.
- Dashboard/observability pages render **unchanged** (still via function-component layouts — no double chrome).

---

# Phase 2 — `refactor/framework-layouts-cleanup`

**Base:** `refactor/framework-layouts-core` (Phase 1)
**Goal:** switch dashboard/observability/session pages to the framework layouts
**atomically with** removing the function-component wrappers, then delete the
legacy layout modules.
**Reference end state:** `0744ed0`.

## Scope

### Changed (router — the enabler)
- `lib/controlkeel_web/router.ex`:
  - `:cloud_auth` → add `layout: {ControlKeelWeb.Layouts, :dashboard}`.
  - Split observability routes out of `:cloud_auth` into `:observability` → `layout: {…, :observability}` + `on_mount: ControlKeelWeb.NavHighlight`.
  - Session routes → `:observability_session` → `layout: {…, :observability_session}` + `NavHighlight`.
  - `invitation_live` → new `:invitations` live_session → `layout: {…, :dashboard}` (no auth `on_mount`).

### Mechanical (~37 LiveViews — wrapper removal)
For each LV, drop the `<*Layout.* …>…</…>` wrapper so `render/1` returns only content.
- **Dashboard LVs** (drop `<DashboardLayout.dashboard flash={@flash}>…</…>`): `dashboard_live`, `missions_live`, `mission_control_live`, `onboarding_live`, `findings_live`, `benchmarks_live`, `proof_browser_live`, `review_live`, `cloud_telemetry_live`, `cloud_projects_live`, `org_members_live`, `org_settings_auth_live`, `org_settings_general_live`, `workspace_repos_live`, `workspace_service_accounts_live`, `workspace_webhooks_live`, `workspace_tool_policy_live`, `policy_studio_live`, `skills_live`, `deployment_live`.
- **Observability LVs** (drop `<ObservabilityLayout.observability …>`): the 16 non-session observability LVs.
- **Session LVs** (drop `<ObservabilitySessionLayout.session …>`, **and** add `:session_id`/`:session_title` assigns in `mount`): `observability_live`, `observability_timeline_live`, `observability_memory_live`.
- `invitation_live.ex` (drop wrapper).

> Pattern (identical across files): remove `~H"""` → `<*Layout.* …>` opening line, and the matching `</*Layout.*>` line before `"""`. Run `mix format` to reindent.

### Deleted
- `components/dashboard_layout.ex`
- `components/observability_layout.ex`
- `components/observability_session_layout.ex`
- their aliases in `controlkeel_web.ex`.

### Docs
- `AGENTS.md` — rewrite the Phoenix layout conventions for framework layouts.

## Steps
1. Router: add the 4 framework `layout:` assignments + `NavHighlight` + `:invitations` live_session.
2. Strip wrappers from the 20 dashboard LVs (batch; `replaceAll` per file).
3. Strip wrappers from the 16 observability LVs (including the 2 multi-line openings in `observability_benchmark_{scenarios,history}_live`).
4. Session LVs: add `:session_id`/`:session_title` assigns + strip wrappers.
5. `invitation_live`: strip wrapper (route already moved in step 1).
6. Delete the 3 legacy modules + aliases; update `AGENTS.md`.
7. `mix format`; `mix precommit`; smoke-test every section.

## Verification
- `mix precommit` green.
- No `<DashboardLayout.` / `<ObservabilityLayout.` / `<ObservabilitySessionLayout.` call sites remain (except docstring examples).
- Sidebar, flash, observability subnav active-link highlighting, and session tabs render on every section.

---

# Phase 3 — `feat/local-auth-toggle`

**Base:** `refactor/framework-layouts-cleanup` (Phase 2)
**Goal:** let a developer enforce the auth/membership gate in local mode via
`CONTROLKEEL_FORCE_AUTH`, and make the public header react to whether auth is
active. Mirrors `refactor/web-auth` commit `49ed2f0`.
**Reference:** `7da4fae`.

## Scope (small — 3 files)
- `lib/controlkeel_web/live_auth.ex`
  - Add `force_auth?/0` — reads `CONTROLKEEL_FORCE_AUTH` (truthy: `true`/`1`/`yes`).
  - Add `auth_enforced?/0` — `Runtime.remote?() or force_auth?()` (true when the gate actually runs).
  - Update `:require_cloud_auth`: `if Runtime.local?() and not force_auth?() do passthrough else enforce`. Alias `Runtime.Mode` → `Runtime`.
- `.env.example` — add the commented `# CONTROLKEEL_FORCE_AUTH=true` entry.
- `lib/controlkeel_web/components/layouts/public.html.heex`
  - Remove the always-on Dashboard nav link.
  - Wrap **Sign in** + **Sign up** in `<%= if ControlKeelWeb.LiveAuth.auth_enforced?() do %>…<% end %>`.
  - Add a **Dashboard** lime-pill button wrapped in `if not ControlKeelWeb.LiveAuth.auth_enforced?()`.

## Behavior
| Mode | Public header |
|---|---|
| Plain local (no `FORCE_AUTH`) | Docs · GitHub · **Dashboard** |
| Local + `CONTROLKEEL_FORCE_AUTH=true` | Docs · GitHub · Sign in · Sign up |
| Cloud / self_hosted | Docs · GitHub · Sign in · Sign up |

## Steps
1. Add `force_auth?/0`, `auth_enforced?/0`; switch the gate + `Runtime` alias.
2. Update `.env.example`.
3. Edit `public.html.heex` (remove Dashboard link; conditional Sign in/up; styled Dashboard button).
4. `mix precommit`.

## Verification
- Plain local run: header shows Dashboard, no Sign in/up; `:require_cloud_auth` is a passthrough.
- `CONTROLKEEL_FORCE_AUTH=true mix phx.server`: header shows Sign in/up, no Dashboard; the gate redirects unauthenticated `/dashboard` to `/auth/login`.

## Known limitation (out of scope)
With `FORCE_AUTH=true` and no OIDC/OAuth provider configured, a developer is
locked out (this branch's only login is org-slug OIDC). `refactor/web-auth`
solved this with Assent OAuth. A dev-only `/auth/dev` route (gated behind
`dev_routes`) is tracked separately — not part of this phase.

---

## Rollout
1. `main` → `refactor/framework-layouts-core` → do Phase 1 → PR → merge.
2. From merged Phase 1 → `refactor/framework-layouts-cleanup` → do Phase 2 → PR → merge.
3. From merged Phase 2 → `feat/local-auth-toggle` → do Phase 3 → PR → merge.
4. Archive/delete the `refactor/framework-layout` reference branch.
