# ControlKeel Studio × Gemini — GDG Stanford / DeepMind Hackathon

> A governed Gemini product assistant: every tool call passes through
> ControlKeel's deterministic governance before anything happens.
> Built with Gemini + Google AI Studio, hosted on **Google Cloud Run**.

## Architecture

```
Judge's browser
      │
      ▼
ck-gemini (Cloud Run · Python google-genai)      ← the "Hosted Prototype"
  Gemini 2.5 Flash + 10 CK governance tools
  Auto-executes tool calls · chat UI · GitHub repo analysis
      │  real HTTP calls to /api/v1/*
      ▼
controlkeel (Cloud Run · Elixir/Phoenix)
  6-layer deterministic scanner · findings · budget enforcement
  review gates · proof bundles · typed memory · Mission Control UI
```

## Live URLs

| Service | URL |
| --- | --- |
| Gemini app (prototype) | <https://ck-gemini-834811228927.us-central1.run.app> |
| Mission Control | <https://controlkeel-834811228927.us-central1.run.app/missions/1> |
| Findings | <https://controlkeel-834811228927.us-central1.run.app/findings> |
| Proofs | <https://controlkeel-834811228927.us-central1.run.app/proofs> |

## Why Cloud Run, not raw AI Studio

Google AI Studio's playground does **not** execute function declarations —
Gemini returns a `functionCall` and you paste responses manually. Only the
`google-genai` Python SDK auto-executes them. So the live prototype is a small
Python app (`app/`) that uses SDK automatic function calling: every CK tool call
really hits the live ControlKeel API. Both services run on Cloud Run, satisfying
the hackathon hosting requirement.

## Deploy (one command)

```bash
export GOOGLE_CLOUD_PROJECT="fluted-torus-424408-s6"
export GEMINI_API_KEY="..."        # https://aistudio.google.com/apikey
./hackathon-demo/deploy.sh
```

Runs `deploy-ck.sh` (backend, ~20–25 min first build) then `deploy-app.sh`
(Gemini app, ~2 min). **Run it the night before** — the CK image builds OTP
from source. Subsequent deploys reuse the image and take ~2 min.

Deploy individually if needed:

```bash
./hackathon-demo/deploy-ck.sh
export CK_BASE_URL="https://controlkeel-834811228927.us-central1.run.app"
./hackathon-demo/deploy-app.sh
```

## What works — verified

| Input | Decision | Layer |
| --- | --- | --- |
| `eval(user_input)` | BLOCK `security.code_execution` | deterministic pattern |
| `api_key = 'sk-proj-...'` | BLOCK (entropy + pattern) | secret detection |
| `rm -rf /` (shell) | BLOCK | destructive-shell tripwire |
| `SELECT ... OR 1=1` | BLOCK `security.sql_injection` | pattern |
| `model.eval()` | ALLOW | no false positive |
| `cursor.execute(sql, params)` | ALLOW | no false positive |
| GitHub URL | risk assessment + review gate | `ck_validate_github_repo` |

All in ~50 ms, **zero LLM tokens**. The `eval`/`exec`/`os.system`/`shell=True`
rule is in the deterministic baseline policy pack — no Semgrep required.

## 10 governance tools

| Tool | What it does |
| --- | --- |
| `ck_validate` | 6-layer deterministic scanner |
| `ck_validate_github_repo` | Fetch + scan public GitHub repo files |
| `ck_context` | Full session state: findings, budget, tasks, proof |
| `ck_budget` | Remaining budget + circuit breaker status |
| `ck_submit_review` | Create review gate in Mission Control |
| `ck_record_finding` | Manually record a finding |
| `ck_memory_record` | Persist typed decision to durable memory |
| `ck_memory_search` | Semantic search over governed memory |
| `ck_generate_proof` | Immutable proof bundle for compliance |
| `ck_complete_task` | Gate task completion on unresolved findings |

## Files

| File | Purpose |
| --- | --- |
| `app/main.py` | Gemini app — SDK auto function calling, GitHub repo fetch, chat UI |
| `app/Dockerfile`, `app/requirements.txt` | Cloud Run container for the app |
| `deploy.sh` | Deploy both services in order |
| `deploy-ck.sh`, `deploy-app.sh` | Deploy each service individually |
| `MASTER_PROMPT.md` | Paste into AI Studio as System Instruction |
| `functions.json` | Function declarations for raw AI Studio |
| `AI_STUDIO_SETUP.md` | How to create the AI Studio share link |
| `DEMO_SCRIPT.md` | 5-minute live walkthrough |
| `CHECKLIST.md` | Demo-day runbook + failure playbook |
| `submission/ONE_PAGER.md` | Hackathon one-pager |

## Honesty notes

- **"1/12 vs 12/12"** comes from `docs/benchmark-evidence.md`
  (host_comparison_v1, runs #29/#31). The raw baseline was not a perfectly
  clean no-CK isolation — present it as documented evidence with the caveat.
- **`/benchmarks`** on a fresh deploy is empty. Lead with live catches on stage.
- `ck_record_finding` and `ck_memory_record` use REST endpoints added for this
  demo (`POST /api/v1/findings`, `POST /api/v1/memory`).
