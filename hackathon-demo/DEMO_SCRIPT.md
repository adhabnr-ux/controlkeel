# ControlKeel Studio — 5-Minute Demo Script

> Every step runs against a live ControlKeel. Tool calls in the Gemini app
> **actually execute** against the API — nothing is mocked.

## Before you start — have these tabs open

| Tab | URL |
|-----|-----|
| AI Studio app (prototype) | https://controlkeel-studio-834811228927.us-west1.run.app |
| Mission Control | https://controlkeel-834811228927.us-central1.run.app/missions/1 |
| Findings | https://controlkeel-834811228927.us-central1.run.app/findings |

Click each tab once to wake them (min-instances=1 keeps them warm).

> Drive everything from the **Gemini app** — not raw AI Studio. AI Studio won't
> execute the tool calls; the Cloud Run app does.

---

## [0:00–0:30] Hook

**Say:** "42% of enterprises have AI agents in production. Almost none have
governance — a markdown rules file is a *promise* to the model, not enforcement.
ControlKeel is the enforcement layer. This Gemini agent physically cannot ship
dangerous code, because ControlKeel blocks it before execution."

**Show:** the Gemini app, then flip to Mission Control.

---

## [0:30–1:20] Demo 1 — Govern a real AI project

In the app sidebar click **LangChain (AI agents)**, or type:

```text
Govern this open source repo: https://github.com/langchain-ai/langchain
```

**What happens:**

- `ck_validate_github_repo` fetches the real README, setup.cfg, etc. from GitHub
- CK scans the fetched files through the governance scanner
- A review gate opens in Mission Control
- Gemini explains risk tier and next steps

**Say:** "This fetches the actual repository files and runs real-time governance
analysis. Judges can try any public repo."

**Flip to Mission Control** — show the pending review.

---

## [1:20–2:10] Demo 2 — Deterministic validation (the core)

Click **Block RCE** in the sidebar, or type:

```text
Validate this code: eval(user_input)
```

**What happens:**

- `ck_validate(content="eval(user_input)", kind="code")` → `decision: block`
- Finding: `security.code_execution` (CRITICAL)
- Red **BLOCK** badge; Gemini explains the RCE risk and safe fix

Now type:

```text
Validate this code: def health(): return {"status": "ok"}
```

→ `decision: allow`, 0 findings → green **ALLOW** badge.

**Say:** "~50 milliseconds, zero LLM tokens. Pattern, not prompt — deterministic
and free. Same result every time."

**Flip to** `/findings` — the blocked finding is there.

---

## [2:10–2:50] Demo 3 — Security quick-fire

Type each; each returns BLOCK with the rule shown in the trace:

| Type this | Catches |
|---|---|
| `Validate: api_key = 'sk-proj-abc123def456ghi789'` | hardcoded secret — entropy detection |
| `Validate this shell: rm -rf /` | destructive shell tripwire |
| `Validate: SELECT * FROM users WHERE id = '' OR 1=1` | SQL injection pattern |

**Then prove precision — no false positives:**

```text
Validate this code: model.eval()
```

→ **ALLOW**. PyTorch method call, not an execution sink.

**Say:** "It catches `eval(` but not `model.eval()`. False positives are how
governance gets turned off — precision matters as much as recall."

---

## [2:50–3:15] Demo 4 — Budget circuit breaker

Type: `Check the budget`

- `ck_budget` → remaining vs spent, session ceiling

**Say:** "Per-session cost tracking with a circuit breaker. When the budget is
spent, the agent stops — it cannot silently run up a bill."

Show the budget line on Mission Control.

---

## [3:15–3:45] Demo 5 — Review gate + memory

Type:

```text
Build a user auth system with JWT tokens and email verification. Create a governed implementation plan.
```

- `ck_submit_review(type="plan")` → pending review in Mission Control

**Flip to Mission Control** — show the pending review → approve it.

**Say:** "Human-in-the-loop. Plans must be approved before execution."

Type:

```text
Remember: we decided to use JWT, RSA-256 signing, 24-hour expiry, refresh token rotation
```

- `ck_memory_record` → persisted, survives sessions and host switches

---

## [3:45–4:15] Demo 6 — "CK blocked our own deploy script"

**Say:** "While building this, we validated our own deploy command — and
ControlKeel blocked us for putting the Gemini API key inline as an env var."

Type:

```text
Validate this shell: gcloud run deploy app --set-env-vars GEMINI_API_KEY=AIzaSyD-realkey123
```

→ **BLOCK** `secret.high_entropy_token` — fix: use Secret Manager.

**Say:** "That's now how the deploy script actually works. It governs the people
building the agent too."

---

## [4:15–5:00] Demo 7 — Platform tour + close

Flash through the CK web UI: `/missions/1` · `/findings` · `/proofs` · `/ship`

**On benchmarks — say exactly this:**

> "In a documented run on a 12-scenario unsafe-code suite, a raw OpenCode +
> GPT-5.5 agent caught **1 of 12**. ControlKeel's deterministic scanner caught
> **12 of 12** in ~50 ms, 0 tokens. You just watched eval, a hardcoded secret,
> destructive shell, and SQL injection blocked live — those catches are
> reproducible. Full methodology is in `docs/benchmark-evidence.md`."

**Close:**

> "ControlKeel is the trust infrastructure for the agent era — deterministic
> enforcement, human review, proof bundles, budget control, 40+ host integrations.
> If you're funding the paved path for enterprise AI, this is it. Thank you."

---

## Numbers you can defend live

| Claim | Evidence |
|---|---|
| `eval(user_input)` → BLOCK | Happened on stage, reproducible |
| `model.eval()` → ALLOW | Happened on stage — proves precision |
| ~50 ms, 0 tokens | Visible in the trace panel |
| 1/12 vs 12/12 | `docs/benchmark-evidence.md` — cite the methodology caveat |
| 40+ host integrations | CK platform docs |
| SOC 2, GDPR, EU AI Act | Compliance packs in CK |

## If something fails live

| Problem | Fix |
|---|---|
| App slow on first hit | Cold start — click once to warm, then demo |
| Tool call errors | App degrades gracefully, CK decision still shows |
| GitHub fetch times out | Try another repo or paste a snippet directly |
| CK backend down | Redeploy with `deploy-ck.sh`; show recorded Playcast |
| Everything broken | Play the recorded 1-min video — never debug on stage |
