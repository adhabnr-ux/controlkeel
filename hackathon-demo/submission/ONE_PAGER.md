# ControlKeel Studio × Gemini — Governed AI Agents

## Team

**ControlKeel** — Bibek Aryal (<bibek@getbamboo.io>)

## One-liner

The enforcement layer that makes AI agents safe for production — a governed
Gemini product assistant where every tool call passes through real-time
ControlKeel governance. Built with Gemini + AI Studio, hosted on Cloud Run.

## Problem

42% of enterprises run AI agents in production; almost none have governance.
A markdown rules file is a promise to the model, not enforcement. When agents
write code, move money, or touch patient data, "I hope the AI followed
instructions" is not a control.

## Solution

ControlKeel sits between the agent and execution. We wired **Gemini 2.5 Flash**
to a live ControlKeel governance backend so every action is validated in real
time:

- **6-layer deterministic scanner** — blocks RCE (`eval`/`exec`), hardcoded
  secrets, destructive shell, SQL injection in ~50 ms, zero LLM tokens,
  while allowing identical-looking benign calls like `model.eval()`.
- **GitHub repo governance** — fetch real repo files and run a risk assessment
  with a single tool call (`ck_validate_github_repo`).
- **Human review gates** — plans approved in Mission Control before execution.
- **Proof bundles** — immutable audit trail for SOC 2 / GDPR sign-off.
- **Budget circuit breakers**, **typed cross-session memory**, **40+ host
  integrations**.

## What we built

1. **ControlKeel Studio** (Python `google-genai`, Cloud Run) — a governed Gemini
   product assistant. Users paste GitHub URLs, code, shell, config, or PR diffs;
   the app runs live ControlKeel governance workflows then uses Gemini to explain
   results and next steps. Real tool execution — not mocked.
2. **ControlKeel backend** (Elixir/Phoenix, Cloud Run) — full governance
   platform: deterministic scanner, findings lifecycle, review gates, proof
   bundles, budget tracking, Mission Control web UI.

## Built with

- Google **Gemini 2.5 Flash** + Google **AI Studio** (function declarations)
- Google **Cloud Run** (both services)
- ControlKeel (Elixir/Phoenix/SQLite) + Python `google-genai`

## Live demo

Open the app and type:

- `Govern this repo: https://github.com/langchain-ai/langchain` — real GitHub
  files fetched, risk assessment, review gate opened in Mission Control.
- `Validate this code: eval(user_input)` — **BLOCKED** in ~50 ms.
- `def health(): return 1` — **ALLOWED**.
- `model.eval()` — **ALLOWED** (proves no false positives).

## Key metric

On a 12-scenario unsafe-code suite, a raw OpenCode + GPT-5.5 agent caught
**1/12**; ControlKeel's deterministic scanner caught **12/12** in ~50 ms, 0
tokens (`docs/benchmark-evidence.md`, host_comparison_v1; note: the raw baseline
was not a perfectly clean no-CK isolation — full methodology in the doc).

## Market

$8.4B AI-governance TAM by 2028 (Gartner). Target: engineering teams shipping
agents in regulated industries. Moat: deterministic enforcement (not LLM
suggestions), cross-agent portability, compliance-grade proof bundles.

## Links

| Item | URL |
| --- | --- |
| **Hosted prototype** | <https://ck-gemini-834811228927.us-central1.run.app> |
| **Mission Control** | <https://controlkeel-834811228927.us-central1.run.app/missions/1> |
| **Code / AI Studio** | _(add AI Studio share link)_ |
| **2-min video** | _(add YouTube link)_ |
| **1-min Playcast** | _(add YouTube link)_ |
