# ControlKeel × Gemini — GDG Stanford / DeepMind Hackathon

> A governed Gemini agent: every tool call passes through ControlKeel's
> deterministic governance before anything happens. Built with Gemini +
> Google AI Studio, hosted on **Google Cloud Run**.

## Why this is structured the way it is

Google AI Studio's playground does **not** execute your function declarations —
when Gemini decides to call a tool it returns a `functionCall` and waits for you
to paste the response by hand. Only the **`google-genai` Python SDK** actually
executes the calls. So the live demo is a small Gemini app (`app/`) that uses the
SDK's automatic function calling: Gemini's tool calls really hit a live
ControlKeel API. Both pieces run on Cloud Run, which is also the hackathon's
hosting requirement.

```
Judge's browser ─▶ Gemini app (Cloud Run, Python google-genai)
                      │  Gemini 2.5 Flash + 9 CK tools (auto-executed)
                      ▼
                   ControlKeel (Cloud Run, Elixir/Phoenix)
                      6-layer deterministic scanner · findings · budget
                      review gates · proof bundles · typed memory
                      Web UI: /missions /findings /proofs /benchmarks /ship
                      API:    /api/v1/*
```

## Two Cloud Run services

| Service | What | Build time |
|---|---|---|
| `ck-gemini` (`app/`) | The Gemini prototype judges interact with. **This URL is the submission's "Hosted Prototype".** | ~2 min |
| `controlkeel` (repo root) | The governance backend the app calls. Elixir/OTP release. | ~20–25 min (first build) |

## Deploy (one command)

```bash
export GOOGLE_CLOUD_PROJECT="your-gcp-project"
export GEMINI_API_KEY="..."          # https://aistudio.google.com/apikey
./hackathon-demo/deploy.sh
```

This runs `deploy-ck.sh` (backend) then `deploy-app.sh` (Gemini app) and prints
both URLs. **Run it the night before** — the CK image builds OTP from source.

Deploy them separately if you prefer:

```bash
./hackathon-demo/deploy-ck.sh                 # prints CK_URL
export CK_BASE_URL="https://controlkeel-xxxx-uc.a.run.app"
./hackathon-demo/deploy-app.sh                # prints the app URL
```

### Fallback for the backend only
If the long Elixir build is a problem, the CK backend can run anywhere that
serves its `/api/v1/*` API (e.g. fly.io via `setup.sh`). Point the Gemini app at
it with `CK_BASE_URL`. The **prototype judges open stays on Cloud Run** either
way, so the hosting requirement is met.

## What works, verified

These were smoke-tested against a live ControlKeel (see `DEMO_SCRIPT.md`):

| You type | CK decision | Layer |
|---|---|---|
| `eval(user_input)` | 🚫 BLOCK `security.code_execution` | pattern (deterministic) |
| `api_key = 'sk-proj-…'` | 🚫 BLOCK (2 findings) | secret entropy |
| `rm -rf /` (shell) | 🚫 BLOCK | destructive-shell |
| `SELECT … OR 1=1` | 🚫 BLOCK `security.sql_injection` | pattern |
| `model.eval()` / `cursor.execute(sql, params)` | ✅ ALLOW | no false positive |
| `def health(): return 1` | ✅ ALLOW | — |

All in ~50 ms with **zero LLM tokens**. The `eval`/`exec`/`os.system`/`shell=True`
rule is deterministic (added to the baseline policy pack) — it does **not** rely
on the optional Semgrep layer, so it works in the Cloud Run container.

## Files

| File | Purpose |
|---|---|
| `app/main.py` | Gemini app — auto-executes 9 CK tools against the live API; chat UI shows the governance trace |
| `app/Dockerfile`, `app/requirements.txt` | Cloud Run container for the app |
| `deploy.sh` | Deploy both services to Cloud Run |
| `deploy-ck.sh` / `deploy-app.sh` | Deploy backend / app individually |
| `MASTER_PROMPT.md` | System instruction (also paste into raw AI Studio) |
| `functions.json` | Function declarations for the raw AI Studio path |
| `DEMO_SCRIPT.md` | 5-minute live walkthrough |
| `submission/ONE_PAGER.md` | Hackathon one-pager |
| `CHECKLIST.md` | Demo-day checklist + fallbacks |

## Honesty notes (so you don't get caught out by a sharp judge)

- The headline "raw agent 1/12 vs CK scanner 12/12" comes from
  `docs/benchmark-evidence.md` (host_comparison_v1, runs #29/#31). The doc itself
  flags that the raw baseline **was not a perfectly clean no-CK isolation**
  (CK/MCP events leaked into some scenarios). Present it as documented evidence,
  and lean on the **live** catches above as the reproducible proof.
- `/benchmarks` on a fresh deploy is **empty** until a run is imported. Don't
  click into it expecting the comparison table during the live demo — show the
  live catches instead.
- `ck_record_finding` and `ck_memory_record` are backed by REST endpoints added
  for this demo (`POST /api/v1/findings`, `POST /api/v1/memory`).
