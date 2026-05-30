# ControlKeel × Gemini — 5-Minute Demo Script

> Every step below was smoke-tested against a live ControlKeel. Tool calls in the
> Gemini app **actually execute** against the API — nothing is mocked.

## Before you start (have these open)

1. **Gemini app** (the prototype): `https://ck-gemini-xxxx-uc.a.run.app`
2. **Mission Control**: `<CK_URL>/missions/1`
3. **Findings**: `<CK_URL>/findings`
4. Warm both with one click each (min-instances=1 should keep them warm).

> Reminder: drive the demo from the **Gemini app**, not the raw AI Studio
> playground. AI Studio won't execute the tool calls; the app does.

---

### [0:00–0:30] Hook

**Say:** "42% of enterprises have AI agents in production. Almost none have
governance — a markdown rules file is a *promise* to the model, not enforcement.
ControlKeel is the enforcement layer. Here's a Gemini agent that physically
cannot ship dangerous code, because ControlKeel blocks it first."

**Show:** the Gemini app, then Mission Control in another tab.

---

### [0:30–1:30] Demo 1 — Govern a real project workflow

In the app, click **Govern a repo** or type:
`Govern this repo: https://github.com/example/agent-app. Create the onboarding plan and review gate.`

Show that the app creates a governed onboarding plan, opens a review gate, checks budget, and tells the user to paste real files/diffs for validation. Then type:
`Build a user registration feature with email login. Create a governed implementation plan.`

This shows it is a usable governed project assistant, not just a scanner.

### [1:30–2:20] Demo 2 — Deterministic validation (the core)

In the app, click **Block RCE** or type `Validate this code: eval(user_input)`.

**What happens (live):**
- Gemini calls `ck_validate(content="eval(user_input)", kind="code")`
- ControlKeel returns `decision: block`, finding `security.code_execution`
- The app shows a red **BLOCK** badge and Gemini explains the RCE risk + fix

**Then type:** `Validate this code: def health(): return {"status":"ok"}`
- `ck_validate` → **ALLOW**, 0 findings → green badge.

**Say:** "~50 milliseconds, zero LLM tokens. Pattern, not prompt — so it's
deterministic and free."

**Switch to** `/findings` — the blocked finding is there.

---

### [2:20–3:00] Demo 3 — Security quick-fire (great for VCs)

Type each; each returns BLOCK with the rule shown in the trace:

| Type this | Catches |
|---|---|
| `Validate: api_key = 'sk-proj-abc123def456ghi789'` | hardcoded secret (entropy) |
| `Validate this shell: rm -rf /` | destructive shell |
| `Validate: SELECT * FROM users WHERE id = '' OR 1=1` | SQL injection |

**Then prove no false positives** — type:
`Validate this code: model.eval()` → **ALLOW** (it's a method call, not RCE).

**Say:** "It catches the dangerous `eval(`, but not PyTorch's `model.eval()`.
Precision matters — false positives are how governance tools get turned off."

---

### [3:00–3:25] Demo 4 — Budget + circuit breaker

Type: `Check the budget`
- `ck_budget` → remaining vs spent, the session ceiling.

**Say:** "Per-session cost tracking with a circuit breaker. When the budget is
spent, the agent stops — it can't silently burn your money."

**Show:** the budget on Mission Control.

---

### [3:25–4:00] Demo 5 — Review gate + memory

Type: `Submit this plan for review: refactor auth to use JWT`
- `ck_submit_review(review_type="plan")` → a **pending** review.

**Switch to Mission Control** → show the pending review → click approve.

**Say:** "Human-in-the-loop. Plans get approved before execution."

Type: `Remember: we decided to use JWT for auth`
- `ck_memory_record` → persisted typed memory (survives sessions/hosts).

---

### [4:00–4:30] Demo 6 — "CK blocked our own deploy script" (the kicker)

**Say:** "While building this, we asked the agent to validate our Cloud Run
deploy command — and ControlKeel blocked *us* for putting the Gemini API key
inline. That's the point: it governs the people building the agent too."

Type: `Validate this shell: gcloud run deploy app --set-env-vars GEMINI_API_KEY=AIzaSyD-realkey123`
- → **BLOCK**, `secret.high_entropy_token`, with a fix prompt to use Secret Manager.

(This is exactly what happened — we now pass the key through Secret Manager.)

---

### [4:30–5:00] Demo 7 — Evidence + platform tour

**Say:** "This isn't a wrapper — it's a platform." Flash through:
`/missions/:id` (task graph), `/findings`, `/proofs`, `/ship`.

**On benchmarks**, be precise: "We benchmark agents on a 12-scenario unsafe-code
suite. In our documented host run, a raw OpenCode + GPT-5.5 agent caught **1 of
12**; ControlKeel's deterministic scanner caught **12 of 12** in ~50 ms with zero
tokens. The raw baseline wasn't a perfectly clean isolation — full methodology is
in `docs/benchmark-evidence.md` — but you just watched the deterministic catches
happen live."

**Close:** "ControlKeel is the trust infrastructure for the agent era —
deterministic enforcement, human review, proof bundles, budget control, and it
ports across 40+ agent hosts. If you're funding the paved path for enterprise AI,
this is it. Thank you."

---

## Numbers you can defend

- **Live, reproducible:** `eval`, hardcoded secret, `rm -rf /`, SQL injection all
  BLOCK in ~50 ms, 0 tokens; `model.eval()` / `cursor.execute(sql, params)` ALLOW.
- **Documented (cite the doc, state the caveat):** raw GPT-5.5 1/12 vs CK scanner
  12/12 — `docs/benchmark-evidence.md`, host_comparison_v1 runs #29/#31.
- **Platform:** 6-layer scanner, review gates, proof bundles, typed memory,
  budget circuit breakers, 8 benchmark suites, 40+ host integrations, compliance
  packs (SOC 2, GDPR, EU AI Act, NIST AI RMF).

## If something fails live
- App slow on first hit → it's a cold start; click once to warm, then demo.
- A tool errors → the app degrades gracefully and still shows the CK decision.
- Worst case → play the recorded 1-minute video (see `CHECKLIST.md`).
