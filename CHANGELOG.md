# Changelog

## v0.3.49 — 2026-06-06

### What's changed

- test(setup): isolate MCP wrapper PATH resolution on CI

## v0.3.48 — 2026-06-06

### What's changed

- fix(setup): detect non-runnable MCP wrapper shims
- fix(skills): clarify duplicate token warning
- fix(cli): reduce skill token overhead
- fix(setup): isolate fresh project runtime state
- fix(migrations): use explicit column lists in SQLite table rebuilds

## v0.3.47 — 2026-06-05

### What's changed

- Add with-vs-without-CK benchmark comparison with cost/time/token deltas
- Revise ControlKeel description for clarity
- Refine README description for ControlKeel
- Revise descriptions in README for clarity

## v0.3.46 — 2026-06-05

### What's changed

- Refactor documentation and UI terminology for clarity and consistency

## v0.3.45 — 2026-06-05

### What's changed

- fix(ci): add --repo flag to gh release upload in sign-release job

## v0.3.44 — 2026-06-05

### What's changed

- fix(test): use DateTime structs for Postgres-compatible insert_all
- fix(maintenance): use to_string comparison for adapter type check
- fix(npm): repair broken regex in cosign path lookup split()
- fix(audit): proof metadata, verification scoring, porcelain filter, attach metadata, install signing, DB safety
- fix(audit): proof metadata, verification scoring, porcelain filter, attach metadata, install signing, DB safety
- fix(cli): honor JSON diagnostics and clean detach artifacts safely
- feat: cosign signing, database maintenance, session event TTL, SQLite VACUUM
- fix(detach): resolve stored agent key and remove the MCP registration

## v0.3.43 — 2026-06-04

### What's changed

- fix: full-potential attach, skill sync, checksum parity, doctor skill consistency
- fix(doctor): keep top-level status "ok"; surface health via install_health
- fix(skills): prune CK's stale skills on re-install, never user-authored ones
- feat(doctor): add install-health checks (git, gitignore, MCP, drift)
- fix(install): verify SHA-256 checksum in shell and PowerShell installers
- fix: gitignore every artifact CK writes into a user repo
- fix: route git shell-outs through crash-safe ControlKeel.Git wrapper
- fix: harden git_context proof capture against missing git and stderr noise

## v0.3.42 — 2026-06-04

### What's changed

- feat: capture git HEAD SHA and working tree state in proof records
- feat: verifiable proof, loop diagnostics, skill eval metadata

## v0.3.41 — 2026-06-04

### What's changed

- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- feat: add agent spec metadata bridge
- feat: add semantic drift scanner guardrails
- feat: enhance review submission with semantic change tracking and governance rules

## v0.3.40 — 2026-06-04

### What's changed

- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- fix: correct dogfood follow-up scope
- fix(self_host): deterministic tar.gz sha256 by zeroing gzip MTIME header

## v0.3.39 — 2026-06-04

### What's changed

- fix: 3 runtime bugs + 2 flaky test assertions from full-suite run
- fix(dogfood): 3 runtime bugs found during full-surface dogfood
- refactor(cli): eliminate 4 more dual-render blocks with render_format/3
- refactor(cli): eliminate 29 dual-render case format do blocks with render_format/3
- feat(annotations+exporter): complete annotation table + cloudflare host module
- Merge refactor/ck-loop-hardening into main
- fix(mcp): normalize advisory to object, fix nullable context_pack fields
- fix(mcp): correct output schema types for nullable and nullable_object fields
- feat(policy-packs): enrich healthcare/finance/education with actionable domain rules
- feat(governance): finish bounded retention, ai_tools, and MCP dedup follow-ups
- fix(mcp): allow object-shaped validate finding locations
- fix(governance): close branch-review blockers before merge
- feat(mcp): return tool execution failures as isError results (Tier B)
- feat(mcp): conservative read-only/destructive tool annotations (Tier A.2)
- test(skills): regression net — every export target produces a plan (Tier A)
- fix: bounded host/SDK/doc parity fixes (Slice P3-G safe fixes)
- feat(memory): detail_level verbosity knob + retention mechanism (Slice P2-F)
- fix(scanner): reliability hardening of the core value prop (Slice P2-E)
- fix(mcp): correct ck_context_pack + ck_execute_code outputSchemas + drift guard (Slice P1-D)
- feat(router): close the learning loop into routing (Slice P1-C)
- feat(sandbox): real runner image, opt-in host-exec enforcement, fail-fast (Slice P0-A)
- feat(findings): agent-callable finding disposition (Slice P0-B of loop-hardening)
- chore(cleanup): remove verified-dead code (Slice 0 of loop-hardening)
- fix: restore deleted exporter modules, eliminate all compiler warnings
- fix(cli): restore 11 command handlers lost in slices 8/9 refactor

## v0.3.38 — 2026-06-02

### What's changed

- docs: add text fence to README bootstrap snippet
- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- feat: slices 7+9+11+12 - CLI parser, exporter targets, plugin registry, sandbox preflight
- feat: slices 4+6+partial-7 - persist tool groups, task/session MCP tools, CLI parser module
- feat: slices 1+3 - MCP outputSchema for all 54 tools, --json consistency
- feat: slices 2+5 - JSON error envelopes, log suppression, shared tool group mapping

## v0.3.37 — 2026-06-02

### What's changed

- Merge pull request #6 from aryaminus/refactor/onboarding-page
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/onboarding-page
- fix(postgres): resolve GROUP BY grouping_error in count_vulnerability_metadata
- refactor/onboarding-page: handle Windows-style line endings when counting key features in router
- refactor/onboarding-page: update missions index to display all sessions and add corresponding integration test
- refactor/onboarding-page: handle missing mission sessions and improve formatting in onboarding live view
- refactor/onboarding-page: remove unused split_list helper function from intent router
- Merge branch 'main' of github.com:aryaminus/controlkeel into refactor/onboarding-page
- refactor/onboarding-page: update UI assertions, refine boundary constraints, and add duplicate project name/continuation tests to onboarding
- refactor/onboarding-page: prevent duplicate mission project names with validation and error handling
- refactor/onboarding-page: add recent sessions dropdown to onboarding and implement mission selection logic
- refactor/onboarding-page: improve boundary summary display and simplify constraints handling
- refactor/onboarding-page: enhance project name validation and update UI to display acceptance criteria
- refactor/onboarding-page: implement missions dashboard and migrate onboarding route to /missions/start
- refactor/onboarding-page: simplify onboarding layout and enhance validation feedback messages
- refactor/onboarding-page: introduce ProviderStatusComponents and integrate into home view

## v0.3.36 — 2026-06-02

### What's changed

- fix(ci): update workflow versions and resolve vs code extension warnings

## v0.3.35 — 2026-06-02

### What's changed

- fix(tests): format project_root assignment for improved readability
- fix(hooks): update codex hook generation to use global path instead of repo path
- Revert "fix: improve MCP connection stability and optimize precommit performance"
- fix: improve MCP connection stability and optimize precommit performance
- fix: update hook commands to use repo_hook_command for consistency
- fix: update hook commands to use repo_hook_command for consistency
- feat: add opt-in agent envelope for web API
- fix: handle bin/controlkeel parse errors cleanly
- fix: make adaptive MCP tool groups learn usage
- chore: clean whitespace, add CK companion instructions to AGENTS.md
- fix: envelope interceptor requires both status+data, bin uses execute/1
- feat: standardize --json success output with stable envelope
- feat: add CLI catalog, scoped help, JSON error envelope, doctor, and capabilities
- refactor: simplify CLI config handling and remove legacy support; update tests accordingly
- feat: add documentation for adaptive tool groups, API reference, CLI reference, autonomy and findings, control plane architecture, large codebase patterns, and QA validation guide; update .gitignore for antigravitycli
- Refactor agent_router.ex by removing unnecessary blank lines; add "ck_tool_health" capability to protocol_interop.ex
- fix: reorder condition in candidate assignment for clarity
- chore: align structure to standard elixir conventions, move local dbs to priv/repo
- docs: remove links to deleted documentation files
- chore(cleanup): remove remaining dead code and policy training references
- chore(cleanup): remove unused ck.policy mix task
- test(cleanup): remove redundant tests while maintaining essential coverage
- chore(cleanup): remove non-essential documentation and restore web modules
- chore: aggressive cleanup of unused modules, dead marketing pages, and policy training subsystem
- test(hooks): fix skills test to assert on generated hook paths and isolate bin environment

## v0.3.34 — 2026-05-31

### What's changed

- refactor: update demo script for clarity and conciseness
- fix: update checklist and one-pager formatting for clarity and consistency
- feat: update URLs and improve documentation for ControlKeel Studio AI app
- feat: update environment configuration and improve error handling in ControlKeel Studio
- feat: initialize ControlKeel Studio with React, Tailwind CSS, and Vite
- feat(hackathon): surface full ControlKeel platform in Studio
- fix: handle protobuf response conversion in tool-call trace extraction
- fix(hackathon): make AI Studio prompt build-ready and app CK-first
- chore(hackathon): align all demo files to ControlKeel Studio
- feat(hackathon): make ControlKeel Studio robust and product-ready
- fix: Mission Control pages work on Cloud Run
- feat(hackathon): make ControlKeel Studio robust and product-ready
- fix(hackathon): Dockerfile runtime deps + ONE_PAGER with live Cloud Run URLs
- fix(hackathon): graceful fallback when Gemini rate-limited
- feat(hackathon): add GDG Stanford hackathon demo for Cloud Run + Gemini
- feat(api): add endpoints for creating findings and memory records

## v0.3.33 — 2026-05-30

### What's changed

- fix(postgres): resolve GROUP BY grouping_error in count_vulnerability_metadata
- fix(postgres): use database-specific JSON fragments for GROUP BY clauses
- fix(postgres): use raw SQL fragment for GROUP BY to avoid parameterization conflicts
- fix(postgres): resolve GROUP BY and datetime parameter issues
- fix(postgres): parameterize string literal in JSON coalesce function
- fix(postgres): resolve JSON query parameterization and string truncation issues
- fix(migrations): increase memory_records text fields to support longer content
- feat(migrations): increase content size for benchmark_scenarios table in SQLite
- fix(migrations): use PostgreSQL-compatible random function for proxy_token generation
- feat(migrations): add proxy_token to sessions and enhance full-text search for findings and tasks
- fix(tests): improve tampering tests for payload and signature in AuthToken verification
- fix(database): rename ECTO_ADAPTER to CK_DB_ADAPTER for consistency across CI and configuration
- fix(ci): update controlkeel-sdk build command to use npm run build
- feat(agent_execution): enhance task processing with input reference management and sorting feat(ck_validate): include trust policy advisory in validation results feat(planner): add trust policy handling and aggregate task marking for releases feat(skills): add continuity skill to skills list docs(challenge): introduce new challenge skill for adversarial review of plans
- feat(migrations): add provenance fields to findings and RLM fields to tasks feat(tools): implement ck_result_peek tool for accessing stdout of completed runs feat(agent): enhance agent execution with stdout writing and loop detection feat(agent_router): add context_window_k to agent configurations feat(ck_context_pack): support excluding IDs and counting hits in context pack feat(mission): extend findings with references to related findings
- docs(planning): add structural planning and agentic patterns from industry insights
- docs(governance): add AI-generated issue/PR quality controls
- feat(skills): add continuity skill for codebase pattern registry
- docs(deployment): move scenario docs to docs/ and bring all sections current
- test(deployment): close SDK, MCP, and cloud-agent scenario gaps
- docs(cloud): update stale tracker TL;DR, HEAD pin, open question, test count
- docs(cloud): avoid stale HEAD pin in readiness tracker
- docs(cloud): pin readiness remediation HEAD
- fix(cloud): close readiness review gaps
- docs(deployment): add deployment scenarios verification status

## v0.3.32 — 2026-05-28

### What's changed

- fix(cloud-sync): hardening pass closing all 10 post-merge findings

## v0.3.31 — 2026-05-28

### What's changed

Cloud-sync hardening — closes four high-severity blocking findings and six
medium issues raised in post-merge review of v0.3.30's `Cloud.Sync`,
`Cloud.SyncEngine`, and `CloudSyncController`.

- fix(cloud-sync, security): close `CK-CLOUD-SYNC-001`. `Cloud.Sync.serialize_record/1`
  now uses a per-schema `sync_fields/0` allowlist instead of `Map.drop` on
  preloads — anything not in the allowlist never ships. Free-form fields
  (`Memory.Record.body`, `Finding.plain_message`, `Review.submission_body`,
  task/agent `metadata`, etc.) are tagged `{:redact, _}` and pass through
  `Cloud.Redactor.redact_value/1`, which scrubs Anthropic/OpenAI `sk-*` keys,
  GitHub PATs, `Authorization: Bearer` headers, and env-style
  `token=`/`secret=`/`api_key=` assignments. Envelopes now stamp both
  `sync_protocol_version` and `redaction_policy_version`.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-002`. Migration
  `20260528270000` adds `external_id` (`ses_<ulid>`) and `synced_at` to the
  `sessions` table, backfilling existing rows with `ses_legacy_<id>`. Without
  this, every other syncable kind's foreign-key chain was broken.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-003`. `do_upsert` for
  append-only kinds now compares the incoming `updated_at` against
  `local.updated_at` instead of skipping on `synced_at != nil`. Cloud-side
  status changes (e.g., `open → blocked`) finally propagate to local.
- fix(cloud-sync, correctness): close `CK-CLOUD-SYNC-004`. `WorkspaceAgent.changeset`
  now casts `:lock_version` (it was missing from the cast list, which silently
  dropped every bump). Optimistic concurrency on agents is real now.
- fix(cloud-sync): close `CK-CLOUD-SYNC-005`/`006`/`007`/`008`. `SyncEngine`
  state-machine rewrite: `state.syncing` actually flips during do_sync so the
  `:already_syncing` guard isn't dead code; the first-ever pull uses the unix
  epoch as the cursor (was: skipped entirely); `last_synced_at` only advances
  on `{:ok, _}` from `do_sync` (was: advanced on failure, leaking records);
  workspace resolution goes through `WorkspaceKeyRegistry.fetch/1` instead of
  `Workspace |> limit(1)`. Unmapped workspaces return `:workspace_not_enrolled`.
- fix(cloud-sync): close `CK-CLOUD-SYNC-009`. `CloudSyncController` drops the
  string-id silent-empty guard. The token's cloud `workspace_id` (string) is
  now resolved to a local `mission_workspace_id` via `WorkspaceKeyRegistry.fetch/1`
  in a new `resolve_db_workspace_id` plug; unmapped tokens get a 404 with a
  clear error. Pull now collects **all four** append-only kinds (findings,
  reviews, session_digests, memory_records) instead of just findings.
- fix(cloud-sync): close `CK-CLOUD-SYNC-010`. `payload_to_attrs` now collects
  unknown fields and logs them at warning level instead of silently dropping
  via `String.to_existing_atom` rescue. Envelope-protocol version mismatch is
  surfaced via `Logger.warning` so version skew is visible.
- fix(cloud-sync): wrap `upsert_batch/2` in `Repo.transaction` so partial
  batch failures roll back; replace per-record changeset writes in `mark_synced/1`
  with a grouped `Repo.update_all` (one round-trip per schema, not per record);
  enforce `max_batch_bytes` (default 8 MB) via JSON-encoded size check.
- test: 24 new tests covering each of the above fixes — round-trip status
  propagation, redactor pattern coverage, workspace_agent lock_version actually
  bumps in the DB, syncing-flag guard fires, first-tick pull uses epoch,
  cursor doesn't advance on failure, unmapped workspace 404s, protocol-version
  mismatch logs. 1951/1951 tests, 0 failures.

### Migration notes

`mix ecto.migrate` applies `20260528270000_add_external_id_to_sessions.exs`.
Backfill happens inline; no manual step required.

## v0.3.30 — 2026-05-28

### What's changed

- feat(cloud-sync): bidirectional cloud sync for governance records.
  New `Cloud.Sync` module collects unsynced findings, memory records,
  reviews, and session digests; serializes them into idempotent envelopes
  keyed by `external_id`; pushes to the cloud endpoint; and pulls remote
  records with local upsert. `Cloud.SyncEngine` GenServer orchestrates
  periodic push/pull (dormant when no `cloud_sync_endpoint` is configured).
  `CloudSyncController` exposes `POST /cloud/v1/sync/push` and
  `POST /cloud/v1/sync/pull` with bearer token auth and 500-record batch limit.
- feat(cloud-sync): workspace-scoped PubSub via `CopilotChannel.subscribe_workspace/1`
  and `broadcast_workspace/3` — topic `ck_workspace:<id>` enables multi-user
  realtime without session-level scoping.
- feat(cli): three new CLI commands — `controlkeel cloud push`,
  `controlkeel cloud pull`, `controlkeel cloud migrate` — for manual sync
  trigger and migration check.
- feat(db): migrations `20260528250000` and `20260528260000` add `external_id`
  (ULID-prefixed: `f_`, `rev_`, `sd_`, `mem_`) + `synced_at` to findings,
  memory_records, session_digests, and reviews; `lock_version` (optimistic
  concurrency) on sessions, tasks, and workspace_agents.

### Migration notes

Run `mix ecto.migrate` to apply the two new migrations. Existing records
receive auto-generated `external_id` values and `lock_version` defaults to 1.
No data loss; columns are nullable during transition.

## v0.3.29 — 2026-05-28

### What's changed

- feat(digest): new `ck_session_digest` MCP tool and `SessionDigest` module.
  Generates condensed, human-scannable digests of what happened in a session —
  tasks completed, findings raised, budget spent, reviews pending, and notable
  highlights. Three digest types: session, daily, shift_change. Sets
  `needs_attention` flag when blocked findings, pending reviews, >80% budget
  consumption, or tech-debt accumulation signals are detected. Also exposes
  `avg_task_duration_seconds` and `tasks_per_hour` in `metadata` so operators
  can observe time-gained vs output-gained without CK pushing either dimension.
- feat(techdebt): new `Governance.TechDebtDetector` and `CK-TECHDEBT-001/002`
  rule family surfaced through `ck_session_digest`. Detects (1) repeated
  patches on the same `Finding.metadata["path"]` across recent sessions
  without an intervening refactor/cleanup commit on that path, and (2) the
  same `rule_id` recurring across ≥3 sessions in the workspace. No new MCP
  tool, no schema migration — reuses `Finding.metadata` and the existing
  `SessionDigest.metadata` map. Inspired by Dax Raad's observation that AI
  code generation mutes the "guilt" of writing a hack, so the muted signal
  has to come from somewhere else.
- feat(rollback): new `ck_rollback` MCP tool and `RollbackExecutor` module.
  Makes rollback executable, not just advisory. Records a git checkpoint
  (commit SHA) before each task via `checkpoint` mode, and provides `execute`
  mode to revert an agent's work with a single action. Safety-checked: refuses
  if downstream completed tasks depend on the changes. Creates an audit finding
  (`CK-ROLLBACK-001`) on every rollback. Inspired by "you need easy rollback."
- feat(agents): new `ck_workspace_agent` MCP tool and workspace agent roles.
  Formalizes agent-role scoping for orgs adopting a forward-deployed-engineer
  pattern, without asserting that pattern as inevitable: `primary` (a single
  maintained agent per workspace), `specialized` (domain-scoped, multiple
  allowed), and `ephemeral` (short-lived task runners). Health monitoring,
  budget tracking, and retirement lifecycle.
- feat(copilot): new `ck_copilot` MCP tool and `CopilotChannel` GenServer.
  Real-time collaborative channel where human actions (viewing, editing,
  approving, commenting) stream to the agent via PubSub without polling. ETS-
  backed event history with auto-pruning. Added to supervision tree. Inspired
  by "build software for humans and agents to use together."
- feat(saas): new `ck_external_service` MCP tool and `ExternalServiceTracker`.
  Tracks and governs agent interactions with external SaaS APIs. Per-service
  rate limiting, cost attribution, latency tracking, and automatic PII
  redaction (tokens, emails) from endpoints. Summary, rate_limit_status, and
  top_services views. Inspired by "agents will create massive new demand for
  SaaS."
- fix(mcp): eliminate 4 compile warnings that were leaking to stdout and
  causing intermittent MCP handshake issues (grouped `run_command/2` clauses
  in cli.ex, grouped `write_target/5` clauses in exporter.ex, removed unused
  default in cloud_runtime_callback_controller.ex).
- fix(agents): replace the over-broad `(workspace_id, role)` unique index on
  `workspace_agents` with a partial unique index scoped to active `primary`
  agents. The original constraint silently blocked the documented case of
  registering multiple specialized or ephemeral agents per workspace.
- fix(db): apply pending migrations for `external_id` on tasks and
  `workspace_github_repos`.

- fix(mcp): update `ck_review_submit` description to name the structured planning fields
  (`research_summary`, `options_considered`, `selected_option`, etc.) that the plan-quality
  scorer evaluates — agents reading the tool description will no longer package everything
  into `submission_body` and get scored weak on first attempts (CK-REVIEW-SCHEMA-002).

## v0.3.28 — 2026-05-28

### What's changed

- feat(cloud): authorize cloud run package creation by org/role
  (`Accounts.authorize_cloud_execution/2`); CLI accepts `--user-id`.
- feat(cloud): link enrolled cloud workspaces to mission workspaces via
  invitation binding. `controlkeel cloud connect --enroll` now reports
  `mission_workspace_id`; `WorkspaceKeyRegistry.fetch_by_mission_workspace/1`.
- feat(cloud): capture git remote/branch/commit_sha on cloud run packages.
  `controlkeel run cloud-agent` shells out to git and accepts
  `--repo-url` / `--branch` / `--commit-sha` overrides.
- feat(cloud): runtime dispatcher seam. New `RuntimeDispatcher` behavior +
  `Manual` default; runtime modules register via `:cloud_dispatchers`
  application config. `controlkeel run cloud-agent --dispatch` chains
  create and dispatch in one command.
- feat(cloud): cloud runtime callbacks accept an optional `findings[]`
  array. `RuntimeContext.ingest_findings/2` persists each finding on the
  package's session tagged with cloud provenance metadata.
- feat(cloud): observable run packages on `/cloud/projects/:ws_id` — new
  "Cloud run packages" card listing each package's status, runtime,
  revision, budget, and timestamps.
- feat(cloud): stable user-facing identifiers — `pkg_<ulid>` on cloud run
  packages, `task_<ulid>` on tasks. Both auto-generated, caller-
  overridable, unique-enforced. Lookup helpers
  `RuntimeContext.get_by_external_id/1` and
  `Mission.get_task_by_external_id/1`.
- feat(cloud): workspace ↔ GitHub repo bindings. New
  `workspace_github_repos` schema + Mission API + CLI (`controlkeel
  govern bind/unbind/list github`). Bound repos ride along in the run
  package payload so downstream runtimes know which repositories to
  fetch.
- feat(cloud): cross-org isolation regression test pins the boundary
  across authz, `list_for_org`, `list_for_workspace`, and the cloud
  projects LiveView.
- fix(cloud): cloud projects table head/body column mismatch and an
  awkward `if/do:` pipe in `mount_index` / `handle_info`.
- chore(format): apply mix format to drift across migrations and tests.
- docs(cloud): callback token lifecycle moduledocs aligned with the
  valid-until-terminal implementation; telemetry controller docs describe
  signed ed25519 AuthToken verification.
- docs(cloud): new `docs/cloud-parity-matrix.md` user-perspective audit
  of every cloud surface with status markers and finding cross-refs.

## v0.3.27 — 2026-05-26

### What's changed

- feat(antigravity): add Antigravity CLI and IDE support with governance bundles
- feat(host-parity): fix crashes and close surface gaps across 26 attachable hosts
- feat(cloud): expand hosted governance surfaces
- feat(setup): strengthen one-line ControlKeel attach flow
- test: update assertions for Claude settings in skills test

## v0.3.26 — 2026-05-25

### What's changed

- feat: implement multi-tenant workspace key management
- feat: enhance findings and policy studio live views with rejection handling and tool policies
- feat(api): add workspace tool policy management and NHI audit event endpoints
- feat: implement JetStream adapter for durable pub/sub queues and add visibility to memory records
- feat: implement Tier 2 deferred items — behavioral baselining, air-gapped pack, NHI lifecycle
- feat: implement Tier 1 deferred items — fallback chain, compliance templates, workspace tool policies
- feat(cloud): update cloud enterprise roadmap with shipped status and deferred items
- feat(agents): add 'agents discover' command for scanning agent-host configurations
- feat(saml): implement SAML authentication flow with controller, client, and CLI support
- feat(auth): implement OIDC authentication flow with session management
- feat: Implement org identity provider configuration and audit export functionality
- feat(cloud): implement runtime context for cloud run packages
- Add comprehensive tests for CLI commands, cloud guardrails, MCP audit logs, policies, and invitation handling
- feat: Add CloudTelemetryLive for monitoring telemetry ingestion health and funnel metrics
- feat: Implement cloud telemetry ingestion and authentication
- Add tests for ControlKeel Cloud components
- feat(docs): enhance cloud enterprise roadmap with positioning, priority elevation, and market validation updates
- feat(docs): expand cloud enterprise roadmap with governance framework and security gates
- feat(docs): update architectural decisions section with resolved defaults and implications
- feat(docs): add open questions and phase acceptance gates to cloud enterprise roadmap
- feat(docs): add cloud-capable runtime surfaces section to support matrix
- feat(docs): enhance cloud and team governance documentation with roadmap and telemetry sync details
- feat(tests): add skill directory name assertion and helper function
- feat: add session list and switch commands with corresponding help documentation
- chore: remove stale research and strategy docs

## v0.3.25 — 2026-05-22

### What's changed

- docs: refine README for clarity and consistency in descriptions
- docs: tighten README opening paragraph
- fix: add ck_engineer_mirror to protocol test and apply formatter changes
- feat: engineer daily mirror + human-side prompt-quality outcomes

## v0.3.24 — 2026-05-22

### What's changed

- fix: eliminate Exqlite sandbox disconnect error in LiveView tests

## v0.3.23 — 2026-05-22

### What's changed

- fix: suppress noisy spawn errors when deepsec cd directory doesn't exist
- fix: repair release readiness proof selection
- feat: enhance npm publishing with trusted publishing and registry configuration
- feat: enhance stream_scan functionality and add tests for findings emission

## v0.3.22 — 2026-05-21

### What's changed

- Merge pull request #3 from aryaminus/refactor/web-homepage
- refactor/web-homepage: remove unused runtime policy section from layout
- refactor/web-homepage: add TODO to replace client-side active link with LiveView-driven approach
- fea/web-homepaget: restore vanilla css
- refactor/web-homepage: move format_percent and format_number functions to PageHTML module
- Update assets/js/app.js
- test: update skills live test
- test: add tests for install page rendering
- refactor/web-homepage: enhance install page layout and styling
- refactor/web-homepage: add module and route for ControlKeel installation, policy and observability
- refactor/web-homepage: implement dynamic sidebar link highlighting and enhance home page layout
- refactor/web-homepage: Refactor layout and home page to enhance dashboard presentation

## v0.3.21 — 2026-05-19

### What's changed

- feat: enhance entropy detection and add tests for credential handling
- chore: replace synthetic seed data with no-op seeds file
- refactor: apply terminology cleanup to source and tests
- chore: remove example files and update remaining demo-script references
- docs: clean up imprecise terminology across docs and remove demo-script
- Merge branch 'main' of https://github.com/aryaminus/controlkeel
- docs: refine documentation on context file usage, SDK vs MCP cost implications, and signal family vocabulary
- feat: update version in plugin.json and enhance documentation for observability and budget alerts
- feat: update documentation and implementation for observability and budget alerts
- docs: add large codebase patterns and best practices for agent deployment
- docs: enhance documentation on SDK vs MCP cost implications and best practices for coding agents
- docs: add production signal observability guidance
- docs: expand agent observability guidance
- feat: enhance benchmark and observability documentation with eval design principles and sampling guidelines
- docs: clarify event-sourced harness posture
- feat: preview Workshop observability snapshots
- style: format MCP resilience changes
- chore: prune stale integration artifacts and harden MCP startup
- Remove legacy deep research report and HELM plan documents; update product strategy plan to clarify focus on current strategy and removal of historical materials.
- feat: enhance virtual workspace with ranking and orientation metadata for search results

## v0.3.20 — 2026-05-07

### What's changed

- docs: enhance documentation with clarity on governed engineering game loop and agentic work
- docs: replace stale release checkpoints with refreshable template
- fix: copy Python runtime executables in generated Dockerfile
- fix: align deployment templates with runtime defaults
- feat: enhance Amp Neo integration with compaction provenance tracking and CK-gated remote-control commands

## v0.3.19 — 2026-05-06

### What's changed

- fix: enhance Zig installation script with caching and retry logic

## v0.3.18 — 2026-05-06

### What's changed

- fix(mcp): fix ToolGroupTracker crash, usage accumulation, and clarify skill references
- chore: re-attach opencode, verify clean AGENTS.md output
- fix(distribution): align Dockerfile with CI, fix npm checksum URL, add Glama docs
- fix(installer): strip broken comment markers without closing --> in sanitize_agents_md
- fix(mcp): harden argument handling and update sync guidance
- feat(amp): enhance Amp Neo integration with updated governance features and documentation
- feat(cli): enhance skills list command to support JSON output format feat(host_audit): implement fallback to GET request for URL checks fix(cli): adjust status command to handle JSON format correctly
- feat(security): add AI tool configuration checks for hardcoded credentials

## v0.3.17 — 2026-05-05

### What's changed

- docs: update governance checklist and enforcement mechanisms in AGENTS.md
- fix(integrations): handle missing deepsec CLI gracefully in tests
- docs: add manual record for governance finding and memory entry
- feat(governance): implement multi-layer safeguards to prevent governance failures
- docs: update governance retrospective with post-implementation actions
- feat(integrations): add deepsec security scanner integration (with governance retrospective)
- Implement feature X to enhance user experience and optimize performance

## v0.3.16 — 2026-05-04

### What's changed

- feat(mcp): enrich tool and property descriptions for Glama TDQS score
- docs: add controlkeel MCP server badge to README

## v0.3.15 — 2026-05-04

### What's changed

- feat: add ToolGroupTracker to application and implement safe calls for adaptive tool group selection
- fix: add standard Apache 2.0 SPDX header to LICENSE for GitHub detection
- docs: update README with adaptive tool groups feature

## v0.3.14 — 2026-05-03

### What's changed

- fix: remove --warnings-as-errors from CI to match local precommit
- feat: enhance documentation for adaptive tool groups and automatic optimization
- feat: Implement adaptive tool group selection and tracking
- feat(token-optimization): update tool groups for improved token savings and documentation
- feat(token-optimization): implement default tool groups configuration and usage examples for token reduction
- feat(mcp): configure tool groups for token optimization; update CLI and tests for new functionality
- feat(token-optimization): complete token overhead audit, multi-host coverage, and config activation
- feat(mcp): enhance skill analysis and token overhead reporting; add duplicate skill diagnostics
- feat(token-audit): implement CK-side tool groups for lazy loading and token savings

## v0.3.13 — 2026-05-02

### What's changed

- fix(ci): handle missing ripgrep in workspace context detection
- fix(mcp): audit and harden discovery, ck_mcp_discover, and ck_skill_validate
- feat(cli): add multica-cloud runtime export command feat(docker): extend sensitive env var checks with suffixes docs(help): update runtime export command documentation with new targets fix(protocol): clarify HTTP transport type description refactor(ck_skill_validate): enhance object validation with additional properties feat(skills): add compatibility for new native integrations across multiple SKILL files
- Enhance documentation on evaluation, governance, and observability
- feat(skills): surface export manifests in doctor output
- feat(skills): write install manifest on export
- feat(mcp): add ck_mcp_discover for MCP server auto-discovery
- fix(security): filter sensitive env vars before forwarding to Docker sandbox
- feat(skills): integrate agent-skills governance patterns into CK skills
- feat(quality): integrate agent-verifier pattern detection into CK
- feat(security): enhance vulnerability taxonomy and remove Strix integration
- chore: remove trailing blank lines in workspace_checkpoint.ex
- feat(skills): add result-schema validation and selective env var exposure
- feat(omnara): add integration analysis and opportunities documentation for ControlKeel
- docs(help): add help topics for worktrees, checkpoints, git workflow, and monitoring
- feat(mcp): register 9 new tools in protocol — worktrees, checkpoints, git, monitoring
- feat(monitoring): add RemoteMonitoring GenServer and ck_monitor_subscribe MCP tool
- feat(git): add governed git workflow with diff/commit/status MCP tools
- feat(worktrees): add ck_worktree_list and ck_worktree_switch MCP tools
- feat(checkpoints): add WorkspaceCheckpoint with create/restore/list and MCP tools
- feat(mission): add TaskCheckpoint CRUD functions
- feat(workspace): add git worktree detection to WorkspaceContext

## v0.3.12 — 2026-05-01

### What's changed

- fix: remove postinstall.js check from CI workflow
- feat: implement lazy download model and enhance security measures for ControlKeel CLI
- docs: streamline explanation in the "Why this exists" section of README
- docs: update README to clarify ControlKeel's role and features

## v0.3.11 — 2026-05-01

### What's changed

- fix: add CI timeouts to prevent 6-hour test hangs
- fix: make observability skill guidance test resilient to empty gitignored dirs

## v0.3.10 — 2026-05-01

### What's changed

- feat: enhance documentation on domain knowledge persistence and agent interaction
- feat: add perf_snapshot persistence to CK memory
- feat: add perf_snapshot observability report and fix test failures
- feat: enhance CLI and MCP modes for improved logging and performance
- feat: add WozCode-inspired tool pattern detection and experience search

## v0.3.9 — 2026-05-01

### What's changed

- fix: version guard only protects plugin bundle; AGENTS.md always written
- fix: harden all host hooks with ck_run + version guard, add local build script
- fix: stop hook sync no longer stomps AGENTS.md or .cursor-plugin hooks
- fix: prevent installed binary from overwriting newer source-synced versions
- perf(db): add composite indexes + SQL aggregate for hot query paths
- feat: enhance README with local observability loop details and CLI commands

## v0.3.8 — 2026-04-30

### What's changed

- fix: make observability skill guidance test CI-safe
- feat: complete observability surface coverage
- chore: sync ControlKeel 0.3.7 surfaces
- feat: strengthen observability learning loop

## v0.3.7 — 2026-04-30

### What's changed

- chore: sync attached ControlKeel surfaces

## v0.3.6 — 2026-04-30

### What's changed

- feat: add ck_observability tool and integrate into MCP protocol
- feat: add local observability feedback loop documentation and commands
- feat: add observability promotions command, UI, and tests
- feat: add observability benchmark history command, UI, and tests
- feat(cli): add new commands for observability benchmarks
- fix: update command paths to handle missing git repository context
- feat: add commands to approve, reject, and archive benchmark drafts with corresponding updates and tests
- feat: add observability regressions command, UI integration, and related tests
- feat: add benchmark draft commands, UI integration, and related tests
- feat: add new observability features including memory quality, trends, and saved eval candidates
- feat: add observability imports command, UI integration, and related tests
- feat: implement observability import with persist option and update related commands and tests
- feat: add observability memory command, context summary, and UI integration
- feat: add observability comparison and timeline commands, UI components, and tests
- feat: add observability costs, eval candidates, and recommendations pages
- feat: add observability import/export commands and overview

## v0.3.5 — 2026-04-29

### What's changed

- fix: update Codex CLI status to verified and clarify checks for sandbox execution
- feat: add observability features and UI components
- fix: update command descriptions for clarity in governance review and submission
- fix: enhance ck_budget check and clarify workflow for delegated implementation
- docs: add cross-runtime continuity verification guide
- test: add cross-runtime continuity tests for budget status and memory source filters
- feat: add source_type and source_id filtering to ck_memory_search
- fix: add ck_budget status mode to check spend without cost inputs
- fix: make skills export/install idempotent with pre-existing destinations
- Refactor MCP tools to resolve session_id from project_root and update input schemas
- feat: Enhance benchmark and cost governance documentation with new guidelines for outcome-first harness loops and multi-agent routing strategies
- feat: Update documentation and security policies, add new packages overview, and enhance .gitignore
- feat: Enhance README and documentation with governance layer details for company context graphs

## v0.3.4 — 2026-04-28

### What's changed

- feat: Add support for Multica native and cloud runtime targets in skill export

## v0.3.3 — 2026-04-28

### What's changed

- feat: Add Multica native and cloud runtime targets to skill catalog
- feat: Enhance skill parsing with owner metadata and content hash computation
- feat: Add Multica integration and content hash to skill definitions
- feat: Add owner field to skill definitions and update related parsing logic
- docs: Update README and support matrix for OpenCode integration details
- Refactor MCP argument handling and tool schemas

## v0.3.2 — 2026-04-28

### What's changed

- feat: Add Warp and Warp Oz integrations
- feat(agent): add support for Devin for Terminal integration with native configuration and hooks
- feat(skill): add handoff skill for session state preservation and background execution
- feat(skills): add align and plan-slice skills for improved project planning and execution
- feat(docs): add details on Pi subagent extensions and their integration with ControlKeel
- feat(tool): add ck_tool_health for governance coverage analysis and implement tests
- feat(docs): enhance benchmark documentation with surface evaluation details and new evaluation script
- feat(agent): add jcode integration with research compatibility and update tests
- feat(docs): update benchmark documentation for clarity on evidence handling and OpenCode procedures
- feat(benchmark): add ck-bounded mode for OpenCode governance and update documentation
- feat(goals): add ck_goal tool for managing durable governed goals and ck_context_pack tool for creating context bundles
- feat(docs): update README and product strategy to clarify ControlKeel's role as software for agents and a company brain for governed delivery
- feat(security): add new rules for mass assignment, rate limiting, sensitive request logging, and IDOR protection
- feat(gdpr): enhance GDPR compliance checks and add new privacy officer domain
- Enhance benchmark subjects and governance harness

## v0.3.1 — 2026-04-26

### What's changed

- feat(review): add alignment context and consulted roles to review packets
- Add Apache-2.0 LICENSE and glama.json for Glama metadata
- Refactor Policy Studio and Proof Browser Live Views to Use Layouts

## v0.2.50 — 2026-04-26

### What's changed

- fix(install): write CLAUDE.md + hooks to project on init/attach

## v0.2.49 — 2026-04-26

### What's changed

- fix(release_smoke): increase timeout and improve process handling

## v0.2.48 — 2026-04-26

### What's changed

- docs(benchmarks): add protocol adapter experiment guidance
- docs(afk): add overnight credibility guidance
- docs(loops): clarify overnight execution posture
- docs(memory): clarify host file memory posture
- docs(integrations): align guarded code execution host surfaces

## v0.2.47 — 2026-04-26

### What's changed

- docs: update ControlKeel workflow guidance
- feat: add guarded code execution tool
- feat: add code-mode governance policy
- fix: avoid stalled plan review waits
- feat: add experience profile support and session hygiene suggestions for cost management
- docs(architecture): enhance planning guidance with interface design and behavior-first focus
- docs(benchmarks): enhance benchmark guidance with premise-refusal and dissatisfaction evals docs(control-plane): clarify task sizing and execution boundaries in architecture fix(exporter): improve context management and planning guidance in exporter module

## v0.2.46 — 2026-04-26

### What's changed

- fix(integrations): avoid stalled review waits and trim context payloads
- chore(cleanup): remove leftover dev mailer config

## v0.2.45 — 2026-04-26

### What's changed

- docs(integrations): clarify benchmark and browser companion guidance
- feat(governance): review GitHub PR URLs directly
- chore(cleanup): remove dead mailer and unused assets

## v0.2.44 — 2026-04-24

### What's changed

- feat(integrations): model dmux as a framework adapter

## v0.2.43 — 2026-04-24

### What's changed

- fix(benchmarks): track repo benchmark subjects for ci
- feat(governance): expand diagnostic findings coverage
- feat(benchmarks): add multi-host comparison workflow

## v0.2.42 — 2026-04-22

### What's changed

- Enhance promotion integrity checks and decision prompts across modules

## v0.2.41 — 2026-04-21

### What's changed

- feat: add diagnostics for daemon role fields in skill metadata and enhance parser validation
- feat: add frontmatter hygiene diagnostics for third-party skills in parser

## v0.2.40 — 2026-04-21

### What's changed

- feat: add interoperability guidelines for external optimizers in benchmarks documentation
- feat: enhance non-server endpoint configuration and update review timeout handling

## v0.2.39 — 2026-04-21

### What's changed

- fix: update documentation for Codex integration and user checkpoints

## v0.2.38 — 2026-04-21

### What's changed

- ci: parallelize release smoke linux and windows builds

## v0.2.37 — 2026-04-20

### What's changed

- fix: soften codex stop hook blocked-findings warning

## v0.2.36 — 2026-04-20

### What's changed

- docs: clarify lean harness guidance for host integrations

## v0.2.35 — 2026-04-20

### What's changed

- test: add comprehensive tests for t3code integration, governance, and runtime conformance
- feat(governance): add canonical event bridge, turn lifecycle, thread state, and budget telemetry
- feat(governance): add approval adapter, idempotency ledger, and remote session claims
- feat(governance): add runtime policy profiles, orchestration event namespace, and wire into recommendations
- feat(integration): promote t3code from alias to first-class attach client
- feat(runtime): add capabilities callback to Runtime behaviour and implement across all runtimes
- feat(docs): enhance documentation on agent integrations, control-plane architecture, and skill package distribution; clarify workflow phases and supply chain considerations

## v0.2.34 — 2026-04-19

### What's changed

- feat(governance): improve code-mode routing and plan-review fallback
- feat(docs): enhance documentation on progressive discovery, human wake-up surfaces, and enterprise control-plane posture feat(core): improve project root resolution logic and enhance advisory status handling test: add tests for CK_PROJECT_ROOT usage in advisory status resolution

## v0.2.33 — 2026-04-19

### What's changed

- fix(mcp): harden launcher fallback and add troubleshooting guidance

## v0.2.32 — 2026-04-19

### What's changed

- feat(cli): add 'attach doctor' command for post-attach verification and health checks
- feat(cli): add status option to watch command and improve error handling for connection failures
- fix(docs): update target from 'codex' to 'opencode' in AGENTS.md and refine setup instructions in README.md
- docs: add one-line setup instructions for ControlKeel in README

## v0.2.31 — 2026-04-18

### What's changed

- feat(runtime): add codex app-server support and sqlite busy retries
- fix(cli): accept positional target for skills export/install subcommands
- fix(test): loosen session_id error message assertion in api_controller_test
- fix: guard jq calls in user-prompt-submit hook against non-JSON context output
- feat: close all Claude integration gaps — write hooks, governance injection, full tool coverage
- feat: add claude-sdk target and SDK integration guidance for Agent SDK
- feat: Add SubagentStart/PostToolUseFailure/ConfigChange/PermissionDenied hooks and fix plugin agent
- feat: Enhance Claude Code integration with full lifecycle hooks, marketplace, and skill metadata
- feat: Enhance Codex CLI integration with lifecycle hooks and configuration updates

## v0.2.30 — 2026-04-18

### What's changed

- chore(registry): align server metadata with 0.2.29 publish

## v0.2.29 — 2026-04-18

### What's changed

- chore(registry): prepare npm package metadata for MCP publish

## v0.2.28 — 2026-04-18

### What's changed

- fix(governance): keep escalated findings human-gated
- Merge branch 'fix/ck-review-store-split'
- fix(mcp): broaden review fallback variants for split runtime contexts
- Merge branch 'fix/ck-review-store-split'
- feat(harness): surface explicit harness principles
- fix(opencode): restore linked CLI execution and tighten governance skill guardrails

## v0.2.27 — 2026-04-18

### What's changed

- feat(update): surface release checks across host agents

## v0.2.26 — 2026-04-17

### What's changed

- docs(cli): add help entries for agent routing and task lifecycle commands
- fix(governance): harden review workflows and runtime host defaults

## v0.2.25 — 2026-04-17

### What's changed

- fix(mcp): prevent review tool endpoint crashes

## v0.2.24 — 2026-04-17

### What's changed

- fix(opencode): mirror legacy config for MCP attach
- fix(opencode): stabilize governed plan-review transport and MCP startup

## v0.2.23 — 2026-04-16

### What's changed

- chore(cursor): align plugin manifest version with app release

## v0.2.22 — 2026-04-16

### What's changed

- fix(governance): auto-resolve matching findings on allow rulings

## v0.2.21 — 2026-04-16

### What's changed

- fix(opencode): harden submit-plan JSON handling in release flows
- docs(opencode): document MCP enabled verification and local attach fallback
- fix(opencode): write enabled MCP entries for local server

## v0.2.20 — 2026-04-16

### What's changed

- fix(mcp): bootstrap installs stdio launcher for CK source; track priv template
- fix(opencode): make local MCP launcher respond under persistent stdio
- fix(cli): force standalone logger output to stderr so `--json` responses stay machine-readable in release flows
- fix(opencode): harden submit-plan JSON parsing and error handling when CLI output includes non-JSON lines

## v0.2.19 — 2026-04-16

### What's changed

- fix(opencode): align native integration with OpenCode surfaces
- feat(hooks): update permission decision for PreToolUse event in ck_copilot_hook.sh

## v0.2.18 — 2026-04-16

### What's changed

- refactor(hooks): remove unused SubagentStop and Stop hooks; enhance logging in ck_copilot_hook.sh
- feat(governance): implement ControlKeel hooks and update version to 0.2.17

## v0.2.17 — 2026-04-16

### What's changed

- Internal maintenance release.

## v0.2.16 — 2026-04-15

### What's changed

- fix(claude): make `attach claude-code` idempotent when MCP server already exists
- fix(mcp): ensure stdio server startup before MCP CLI handoff and improve launcher stdio reliability
- chore(qa): add full Copilot parity script with bounded MCP/attach checks for deterministic audit runs

## v0.2.15 — 2026-04-15

### What's changed

- feat(update): add release-aware upgrade flow

## v0.2.14 — 2026-04-15

### What's changed

- feat(cli): add context and validate commands

## v0.2.13 — 2026-04-15

### What's changed

- fix(mcp): filter mix stdout in bin/controlkeel-mcp for stdio JSON

## v0.2.12 — 2026-04-15

### What's changed

- fix(mcp): stderr logging in CK_MCP_MODE; align Cursor integration docs
- fix(mcp): stdio newline-delimited JSON-RPC per MCP spec
- fix(mcp): handle JSON-RPC 2.0 batches (Cursor handshake)
- fix(mcp): avoid Registry scans on tools/list and resources/list in stdio
- chore(mcp): stderr boot timing, app.start --no-compile, SQLite busy_timeout
- fix(mcp): defer Repo/bus boot so Cursor can finish initialize
- fix(mcp): source-tree launcher uses mix ck.mcp, not release bin
- fix(mcp): dogfood source tree prefers local release/mix over PATH controlkeel
- fix(mcp): prefer local mix release binary over mix ck.mcp when present
- fix(mcp): use IO.binwrite for stdio and binary io opts in reader
- fix(mcp): flush stdout after each framed JSON-RPC response
- fix(mcp): skip Phoenix CodeReloader when CK_MCP_MODE for faster Mix boot
- fix(mcp): defer release migrations until after MCP children start
- fix(mcp): supervise stdio server before Repo under CK_MCP_MODE
- fix(mcp): prefer repo bin launcher for Cursor in ControlKeel source tree
- fix(mcp): keep stdio stdout JSON-only for Cursor handshake

## v0.2.11 — 2026-04-15

### What's changed

- fix(mcp): skip attached-agent sync during stdio MCP startup

## v0.2.10 — 2026-04-15

### What's changed

- fix(install): scrub AGENTS.md before ControlKeel block; portable project hint

## v0.2.9 — 2026-04-15

### What's changed

- fix(mcp): Cursor stdio — workspaceFolder launcher path and CK_PROJECT_ROOT scan

## v0.2.8 — 2026-04-15

### What's changed

- chore: align Cursor plugin manifest version with app (0.2.7)
- Fix Cursor MCP stuck on Loading tools (quiet stdout for stdio MCP)

## v0.2.7 — 2026-04-15

### What's changed

- cli: use pipe separator in status and watch output

## v0.2.6 — 2026-04-15

### What's changed

- Fix Cursor bundle: priv skill precedence, portable MCP paths
- feat: enhance task verification and assurance features
- feat: add retrieval strategy configuration and support for multiple strategies in ControlKeel
- chore: update .gitignore, enhance AGENTS.md, and improve logger configuration in runtime.exs

## v0.2.5 — 2026-04-13

### What's changed

- Add Cursor plugin, fix MCP server encoding, and expand Cursor integration surface

## v0.2.4 — 2026-04-12

### What's changed

- Improve Codex install surfaces and governance docs

## v0.2.3 — 2026-04-11

### What's changed

- Expose Cloudflare runtime export in CLI
- Add skill quality diagnostics
- Add harness policy to intent boundary
- Fix init and attach project-root parsing

## v0.2.2 — 2026-04-11

### What's changed

- Expose skills as MCP resources
- Add provider trust-boundary reporting
- Add split-aware eval profiles to benchmarks
- Quiet CLI smoke output in test runs
- Add governed decomposition summaries to mission state

## v0.2.1 — 2026-04-10

### What's changed

- Add Letta Code native attach support

## v0.2.0 — 2026-04-10

### What's changed

- Add Executor runtime export support
- Add virtual bash runtime export
- Align runtime export docs and API metadata

## v0.1.43 — 2026-04-09

### What's changed

- Add JSON output mode for core CLI reads

## v0.1.42 — 2026-04-09

### What's changed

- Improve CLI proofs progress and benchmark ergonomics

## v0.1.41 — 2026-04-09

### What's changed

- Make CLI status and findings more agent ergonomic

## v0.1.40 — 2026-04-08

### What's changed

- Add derived task augmentation context

## v0.1.39 — 2026-04-08

### What's changed

- Add autonomy and improvement loop summaries

## v0.1.38 — 2026-04-08

### What's changed

- Surface security case triage summaries

## v0.1.37 — 2026-04-07

### What's changed

- Tighten security workflow proof gating

## v0.1.36 — 2026-04-07

### What's changed

- Add defensive security workflow to ControlKeel
- Add detailed ControlKeel architecture walkthrough
- Add plain-English ControlKeel explainer

## v0.1.35 — 2026-04-07

### What's changed

- Harden agent-facing validation and context resolution

## v0.1.34 — 2026-04-07

### What's changed

- Align web project-root context with CLI

## v0.1.33 — 2026-04-07

### What's changed

- Harden Codex dogfooding surfaces

## v0.1.32 — 2026-04-07

### What's changed

- Use canonical docs for wrapper aliases
- Add public host drift audit
- Make runtime recommendations availability-aware

## v0.1.31 — 2026-04-07

### What's changed

- Make typed storage explicit in execution posture

## v0.1.30 — 2026-04-07

### What's changed

- Add execution posture guidance to intent context

## v0.1.29 — 2026-04-07

### What's changed

- Ignore generated editor companion artifacts
- Harden OpenCode submit_plan execution

## v0.1.28 — 2026-04-07

### What's changed

- Improve OpenCode plan review integration
- Add .copilot/skills to project skill directories

## v0.1.27 — 2026-04-07

### What's changed

- Ignore local attach artifacts in repo
- Fix Codex self-hosting attach and install paths

## v0.1.26 — 2026-04-07

### What's changed

- Align Codex integration with native skills

## v0.1.25 — 2026-04-07

### What's changed

- Handle virtual workspace grep without ripgrep
- Clarify hosted MCP scope guidance
- Apply formatting after precommit
- Refresh integrations and export Droid plugin bundles
- Add governed MCP control-plane surfaces

## v0.1.24 — 2026-04-06

### What's changed

- Refactor research note and submission payload for clarity and accuracy
- Add research note and benchmark details for ControlKeel governance
- Add ControlKeel benchmarking artifacts and analysis scripts

## v0.1.23 — 2026-04-05

### What's changed

- feat: add Kilo Code integration with native support and enhance documentation
- feat: enhance documentation and tests for skills.sh integration and aliases

## v0.1.22 — 2026-04-05

### What's changed

- docs: update installation documentation with direct host package details and commands
- feat: introduce setup command for bootstrapping ControlKeel and enhance project root resolution

## v0.1.21 — 2026-04-05

### What's changed

- Enhance ControlKeel governance and memory management
- feat: add QA validation guide and update documentation references

## v0.1.20 — 2026-04-03

### What's changed

- Refactor documentation and code for ControlKeel integrations
- feat: add guided help system and enhance help command functionality

## v0.1.19 — 2026-04-03

### What's changed

- feat: enhance Codex CLI integration with config management and installation support

## v0.1.18 — 2026-04-03

### What's changed

- feat: add augment-native and augment-plugin support
- Add annotate and last commands for various skills in ControlKeel
- feat: add explicit review commands and enhance feedback handling in ControlKeel
- Add agent adapters and runtimes for OpenCode, Pi, and VSCode
- Add review lifecycle functionality and associated tests

## v0.1.17 — 2026-04-02

### What's changed

- docs: clarify release installs and bundle coverage

## v0.1.16 — 2026-04-01

### What's changed

- feat: add OpenCode integration support and enhance CLI configuration handling

## v0.1.15 — 2026-04-01

### What's changed

- feat: add new framework adapters and enhance security rules for leak-derived dependencies
- feat: add Socket dependency review command and related tests
- feat: enhance documentation and add security rules for SSRF and dependency hygiene

## v0.1.14 — 2026-04-01

### What's changed

- fix: improve plugin installation error handling and output messages
- docs: update attach commands and release verification checkpoints
- fix: update badge links in README for Release Smoke and Latest Release

## v0.1.13 — 2026-04-01

### What's changed

- fix: specify repository in gh run download command for artifact retrieval

## v0.1.12 — 2026-04-01

### What's changed

- feat: update workflow triggers for Release Smoke and Bump Version processes

## v0.1.11 — 2026-04-01

### What's changed

- feat: implement retry logic for finding successful Release Smoke run in release workflow

## v0.1.10 — 2026-04-01

### What's changed

- feat: rename parameter in Test-TcpPortOpen function for clarity and update references in Test-ProcessListeningPort function
- feat: enhance Test-TcpPortOpen function with null check for connectTask and improved client disposal logic
- feat: add Test-ProcessListeningPort function for enhanced server process checks in release smoke script
- feat: add Test-TcpPortOpen function for improved server connectivity checks in release smoke script
- feat: improve logging in release smoke script by separating stdout and stderr
- feat: add overwrite option to mix release commands in release smoke script
- feat: update release smoke scripts to improve server process handling and error reporting
- feat: improve error handling for daemon startup in release smoke script
- feat: enhance CI workflow, add file overwrite handling, and improve tests for deployment advisor
- feat: update CI workflow and add verification script for required patterns
- feat: remove redundant help command from release smoke script
- feat: finalize governance/docs reconciliation and quality fixes
- feat: enhance cost optimizer and outcome tracker tools with improved handling and new workspace_id defaults
- feat: add comprehensive test suite for deployment advisor, findings translation, and project governance modules
- feat: add MCP tools for cost optimization, outcome tracking, and deployment advisory with updated skill documentation
- feat: implement learning, cost management, deployment guidance, and governance modules to close system gap analysis
- feat: implement deployment advisor with automated infrastructure generation and project monitoring tools
- docs: add pathfinder gap analysis and research documentation
- docs: add documentation for mcptocli integration to agent-integrations.md
- feat: implement OWASP-style classification metrics and add benign baseline benchmark suite
- refactor: update agent support matrix to native integration and simplify README documentation
- feat: upgrade Kiro, Amp, OpenCode, and Gemini-CLI integrations to native-first mode with expanded export and installation support.
- feat: implement pluggable execution sandbox system with E2B, local, and Docker support, and add Gemini proxy capabilities
- refactor: Update documentation and remove deprecated components
- feat: Implement agent execution API and delegate tool

## v0.1.9 — 2026-03-27

### What's changed

- docs: refresh release verification and agent scope matrix
- docs: refresh Release Smoke SHA, align ck-final Mission Control, missing/ hygiene

## v0.1.8 — 2026-03-25

### What's changed

- feat: benchmark quick presets, datalist hints, ignore session exports
- docs: support matrix, check.md classification, opencode archive note
- docs: include idea/missing/check.md FAQ in version control
- feat: P1 docs, mission graph UX, validate advisory metadata, release SHAs
- feat: update .gitignore and add opencode.md for project scope and requirements

## v0.1.7 — 2026-03-24

### What's changed

- feat: complete launch-ready OpenCode onboarding and benchmark flow

## v0.1.6 — 2026-03-24

### What's changed

- feat: add ops alignment runbook and Phoenix policy template
- feat: Introduce provider brokering with ephemeral project bindings and agent auto-bootstrap capabilities.

## v0.1.5 — 2026-03-19

### What's changed

- Reduce GitHub Actions Node 20 warnings
- Record green v0.1.4 release verification

## v0.1.4 — 2026-03-19

### What's changed

- Fix Homebrew release publish and add GitHub Packages

## v0.1.3 — 2026-03-19

### What's changed

- Record latest green release smoke SHA
- Fix workflow guard expressions
- Harden release workflow triggers
- Optimize release automation workflows

## v0.1.2 — 2026-03-19

### What's changed

- Fix Windows release archive path

## v0.1.1 — 2026-03-19

### What's changed

- Implement phase 3 platform and release closure
- Revise ControlKeel status audit to reflect closed MVP gaps and remove stale claims
- Expand audit log details and clarify Phase 2 implementation gaps in the ControlKeel status document
- Update release workflows for Node 24
- Treat Burrito as release runtime for migrations
- Cancel stale release workflow runs
- Run release migrations before starting endpoint
- Fix project binding path resolution on Windows
- Fix release smoke secret and diagnostics
- Run release CLI commands synchronously
- Skip Claude auto-attach in release smoke
- Resolve release smoke binary paths
- Halt standalone release commands synchronously
- Fix Burrito standalone argv handling
- Fix Burrito standalone CLI detection
- Finish agent integration surface and fix release smoke
- Fix Zig installer in release workflows
- Fix Burrito release packaging CI
- feat: add ControlKeel skills and benchmarks for governance and compliance
- feat: enhance mission and policy training features
- feat: add skills management and governance tools
- feat(api): update task completion logic to handle string task IDs
- feat: Cursor/Windsurf attach, episodic memory, benchmark scenarios, 12 domain packs, 28 Semgrep rules
- feat: agent router (Layer 3), proof bundles, audit log, HR/Legal/Marketing policy packs
- fix: downgrade Burrito 1.5.0→1.3.0, switch Zig to 0.14.0

## v0.1.0 — 2026-03-18

First public release.

### What's included

**Core governance engine**
- Three-tier scanner: FastPath (<5ms Elixir patterns + entropy analysis) → Semgrep SAST (29 rules across 9 languages) → Advisory LLM (optional 3rd tier)
- 12 policy packs, 62 rules total: Baseline Secrets, Baseline Injection, Cost, Software, Healthcare, Finance, Education, GDPR, HR, Legal, Marketing, Sales, Real Estate
- Per-session and rolling 24h budget enforcement with warn/block decisions
- MCP server (JSON-RPC 2.0 over stdio) with five tools: `ck_validate`, `ck_context`, `ck_budget`, `ck_finding`, `ck_route`
- HTTP proxy for OpenAI and Anthropic APIs — scans both request and response content

**Agent Router (Layer 3)**
- Automatic agent selection by task type, security tier, budget, and capability
- Supports 7 agents: claude-code, cursor, codex, bolt, replit, ollama, generic-cli
- Security tier enforcement: critical tasks route only to local agents (ollama, claude-code, cursor)
- Budget-aware: falls back to free local agents (ollama) when budget is low
- Exposed via `POST /api/v1/route-agent` and the `ck_route` MCP tool

**Web UI (5 LiveViews)**
- `/start` — Mission launch wizard with domain selection, agent picker, daily budget input
- `/missions/:id` — Real-time mission control with compliance score donut, task list, approve/reject findings
- `/findings` — Cross-session findings browser with severity/status/category filters
- `/policies` — Policy Studio showing active packs, rule counts, session budgets
- `/ship` — Install-to-first-finding funnel metrics

**REST API** (`/api/v1/`) — 13 endpoints
- Sessions CRUD, task creation + update + complete (gated), content validation
- Findings with actions (approve/reject/escalate), budget summary
- Proof bundle per task (`GET /proof/:task_id`)
- Audit log per session JSON + CSV (`GET /sessions/:id/audit-log`)
- Agent routing (`POST /route-agent`)

**Task completion gate**
- `Mission.complete_task/1` blocks marking a task "done" if any open or blocked findings exist
- Returns the list of unresolved findings so the caller can surface them

**Proof Bundle**
- Structured audit artifact per task: security findings, risk score, cost, deploy readiness, compliance attestations per domain pack

**Audit Log**
- Chronological invocations + findings for a session
- JSON (default) or CSV (`?format=csv`) for export into compliance tooling

**Episodic Memory**
- `ck_context` injects `past_patterns`: top recurring blocked rules from the last 10 sessions in the same domain pack
- SQL-based implementation (no pgvector required) using SQLite GROUP BY + ORDER BY

**CLI** (11 commands)
- `init`, `attach`, `status`, `findings`, `approve`, `watch`, `mcp`, `version`, `help`
- `attach claude-code` — registers MCP server with Claude Code
- `attach cursor` — writes to `~/.config/Cursor/User/globalStorage/cursor.mcp.json`
- `attach windsurf` — writes to `~/.codeium/windsurf/mcp_config.json`
- Binary packaging via Burrito — no Erlang required on target machine

**Developer experience**
- `mix ck.smoke` — benchmark smoke check for real-world governance failure scenarios (hardcoded keys, SQL injection, client-side auth bypass, unencrypted PHI, eval() RCE, open redirect, Supabase public bucket, PII to Segment, DEBUG=True in prod, pickle.loads deserialization RCE)
- `mix ck.watch` / `controlkeel watch` — live stream of findings and budget in the terminal
- 159 tests, 0 failures

### Semgrep rules (29 across 9 languages)

**Generic**: SQL injection, XSS sinks, `dangerouslySetInnerHTML`, inline scripts, hardcoded secrets, hardcoded JWT, `eval()`, `subprocess(shell=True)`, `os.system()`, `pickle.loads()`, `curl | bash`, `rm -rf`, prototype pollution, debug mode in prod, open redirect, hardcoded credentials

**Go**: sql.Query string format, hardcoded secret, exec injection

**Rust**: unwrap in handler, unsafe block, hardcoded secret

**Java**: SQL string concatenation, hardcoded secret, XXE

**Shell**: missing `set -e`

**HCL (Terraform)**: public S3 bucket

**Dockerfile**: running as root

**Ruby**: SQL string concatenation

**PHP**: `eval()` with user input

### Policy Packs (12 packs, 62 rules)

| Pack | Rules | Key concerns |
|------|-------|-------------|
| Baseline — Secrets | 5 | AWS keys, high-entropy tokens, hardcoded credentials |
| Baseline — Injection | 4 | SQL injection, eval/exec, unsafe HTML |
| Cost | 3 | Budget overrun, cost tracking |
| Software | 6 | Debug endpoints, CORS wildcard, console.log PII |
| Healthcare | 6 | HIPAA, PHI patterns, unencrypted patient data |
| Finance | 6 | PCI DSS, plaintext card numbers |
| Education | 6 | FERPA, student data exposure |
| GDPR | 6 | PII logging, unencrypted PII fields, third-party data sharing |
| HR | 6 | Employment PII, discriminatory criteria, salary data |
| Legal | 6 | Privileged content logging, e-discovery deletion |
| Marketing | 6 | Email unsubscribe, cookie consent, PII in analytics |
| Sales | 6 | CRM PII, revenue data logging, unsolicited email |
| Real Estate | 6 | Fair Housing criteria, SSN unencrypted, tenant data |
