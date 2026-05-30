# ControlKeel × Gemini — Governed AI Agents

## Team
**ControlKeel** — [Your Name]

## One-liner
The enforcement layer that makes AI agents safe for production — a governed
Gemini agent whose every tool call passes through real-time governance. Built
with Gemini + Google AI Studio, hosted on Google Cloud Run.

## Problem
42% of enterprises run AI agents in production; almost none have governance. A
markdown rules file is a *promise* to the model, not enforcement. When agents
write code, move money, or touch patient data, "I hope the AI followed
instructions" is not a control.

## Solution
ControlKeel sits between the agent and execution. We wired **Gemini** to a live
ControlKeel instance so every action is governed:
- **6-layer deterministic scanner** — blocks RCE (`eval`/`exec`), hardcoded
  secrets, destructive shell, SQL injection in ~50 ms with **zero LLM tokens**,
  while allowing lookalikes like `model.eval()` (no false positives).
- **Human review gates** — plans approved before execution.
- **Proof bundles** — immutable audit trail for compliance.
- **Budget circuit breakers**, **typed cross-session memory**, **40+ host
  integrations**.

## What we built for this hackathon
1. **Gemini governed-agent app** (Python `google-genai`, Cloud Run) — uses the
   SDK's automatic function calling so Gemini's 9 governance tool calls *really*
   execute against ControlKeel. This is the live prototype judges interact with.
2. **ControlKeel backend** (Elixir/Phoenix, Cloud Run) — the full governance
   platform: scanner, findings, reviews, proofs, budget, Mission Control UI.

## Built with
- Google **Gemini 2.5 Flash** + Google **AI Studio** (function declarations)
- Google **Cloud Run** (both services)
- ControlKeel (Elixir/Phoenix/SQLite) + Python `google-genai`

## Live demo
Open the app and type `Validate this code: eval(user_input)` → **🚫 BLOCKED**
(`security.code_execution`). Try `def health(): return 1` → **✅ ALLOWED**. Then
`rm -rf /`, a hardcoded key, SQL injection — all blocked, live, in the UI.

## Key metric
On a 12-scenario unsafe-code suite, a raw OpenCode + GPT-5.5 agent caught **1/12**;
ControlKeel's deterministic scanner caught **12/12** in ~50 ms, 0 tokens
(`docs/benchmark-evidence.md`, host_comparison_v1; raw baseline not a perfectly
clean isolation). The deterministic catches are reproducible live.

## Market
$8.4B AI-governance TAM by 2028 (Gartner). Target: engineering teams shipping
agents in regulated industries. Moat: deterministic enforcement (not LLM
suggestions), cross-agent portability, compliance-grade proof bundles.

## Links
- **Hosted prototype (Cloud Run):** https://ck-gemini-834811228927.us-central1.run.app
- **Mission Control:** https://controlkeel-834811228927.us-central1.run.app/missions/1
- **Findings:** https://controlkeel-834811228927.us-central1.run.app/findings
- **Code:** [GitHub / AI Studio share]
- **Video:** [YouTube]
