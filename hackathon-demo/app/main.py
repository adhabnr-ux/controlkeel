"""
ControlKeel × Gemini — Governed Agent (Cloud Run)
=================================================
A small Gemini app that wires Google's Gemini model to a live, hosted
ControlKeel instance using the google-genai SDK's *automatic* function calling.

Why this exists: in Google AI Studio (and the REST API) function calls are NOT
auto-executed — the model returns a functionCall and waits for you to supply the
response by hand. Only the Python google-genai SDK executes the calls for you.
This app is that executor: every Gemini tool call really hits ControlKeel's
/api/v1/* endpoints, so the governance is real, not a mock.

Deliverable mapping for the hackathon:
  - "Build with Gemini"         -> this app uses google-genai + Gemini
  - "Hosted on Google Cloud Run"-> Dockerfile + deploy-app.sh ship it to Cloud Run
  - Live demo surface           -> the / chat UI shows the governance trace

Routes:
  GET  /          chat UI
  POST /chat      run one governed Gemini turn -> {response, trace}
  GET  /healthz   liveness (also warms the CK session)
"""

from __future__ import annotations

import os

import requests
from flask import Flask, jsonify, render_template_string, request

# ── Configuration ──────────────────────────────────────────────────────────
CK_BASE_URL = os.environ.get("CK_BASE_URL", "http://localhost:4000").rstrip("/")
CK_API_KEY = os.environ.get("CK_API_KEY", "").strip()
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

# Session/task the demo runs against. Bootstrapped lazily on first use so a cold
# Cloud Run instance recovers on its own without a manual setup step.
_STATE: dict[str, int | None] = {"session_id": None, "task_id": None}

app = Flask(__name__)


# ── ControlKeel REST client ─────────────────────────────────────────────────
def _ck_headers() -> dict[str, str]:
    headers = {"Content-Type": "application/json"}
    # Only send a bearer token when one is configured. ControlKeel's ApiAuth
    # plug 401s on a *bogus* token even in open/local mode, so an empty key must
    # mean "no Authorization header" rather than "Bearer ".
    if CK_API_KEY:
        headers["Authorization"] = f"Bearer {CK_API_KEY}"
    return headers


def _ck_get(path: str, params: dict | None = None) -> dict:
    r = requests.get(f"{CK_BASE_URL}{path}", headers=_ck_headers(), params=params, timeout=30)
    return _as_json(r)


def _ck_post(path: str, body: dict | None = None) -> dict:
    r = requests.post(f"{CK_BASE_URL}{path}", headers=_ck_headers(), json=body or {}, timeout=30)
    return _as_json(r)


def _as_json(r: requests.Response) -> dict:
    try:
        data = r.json()
    except ValueError:
        return {"_status": r.status_code, "_error": "non-json response", "_body": r.text[:300]}
    if isinstance(data, dict):
        data.setdefault("_status", r.status_code)
        return data
    return {"_status": r.status_code, "data": data}


def _ensure_session() -> tuple[int | None, int | None]:
    """Lazily resolve the demo session + a task id. Idempotent.

    Uses POST /api/v1/bootstrap, which creates a workspace + session + initial
    tasks on a fresh instance (and returns the existing one otherwise). Direct
    POST /api/v1/sessions is avoided because it requires a workspace_id the
    client doesn't have.
    """
    if _STATE["session_id"]:
        return _STATE["session_id"], _STATE["task_id"]

    # Allow pinning via env for a stable Mission Control URL across restarts.
    if os.environ.get("CK_SESSION_ID"):
        _STATE["session_id"] = int(os.environ["CK_SESSION_ID"])
        if os.environ.get("CK_TASK_ID"):
            _STATE["task_id"] = int(os.environ["CK_TASK_ID"])

    if not _STATE["session_id"]:
        booted = _ck_post("/api/v1/bootstrap", {"project_name": "gemini-demo", "agent": "gemini"})
        session = booted.get("session") or booted
        _STATE["session_id"] = session.get("id") if isinstance(session, dict) else None

    sid = _STATE["session_id"]
    if sid and not _STATE["task_id"]:
        detail = _ck_get(f"/api/v1/sessions/{sid}")
        tasks = (detail.get("session") or detail).get("tasks") or []
        if tasks:
            # Prefer an active task; otherwise take the first one.
            active = next((t for t in tasks if t.get("status") in ("in_progress", "queued")), tasks[0])
            _STATE["task_id"] = active.get("id")

    return _STATE["session_id"], _STATE["task_id"]


# ── Tools exposed to Gemini (auto-executed by google-genai) ──────────────────
# Each function below is handed to the SDK as a tool. Gemini decides when to
# call them; the SDK runs the Python function and feeds the result back. The
# docstrings ARE the tool descriptions the model sees, so keep them sharp.

def ck_validate(content: str, kind: str = "code") -> dict:
    """Validate code, config, a shell command, or text against ControlKeel's
    6-layer deterministic scanner (pattern rules, secret-entropy, destructive
    shell tripwires, trust boundary, security workflow, optional Semgrep).
    Runs in ~50ms with zero LLM tokens. Call this BEFORE writing files or
    running commands. Returns {decision: allow|warn|block, findings: [...]}.

    Args:
        content: The exact code/config/shell/text to scan.
        kind: One of "code", "config", "shell", "text".
    """
    return _ck_post("/api/v1/validate", {"content": content, "kind": kind, "source_type": "generated"})


def ck_context() -> dict:
    """Load the governed session state: active findings, budget, tasks, and
    proof summary. Call at the start of a task to see the current posture."""
    sid, _ = _ensure_session()
    if not sid:
        return {"error": "no session"}
    return _ck_get(f"/api/v1/sessions/{sid}")


def ck_budget() -> dict:
    """Check remaining budget and spend for the session. ControlKeel tracks
    per-invocation cost and fires a circuit breaker when the budget is spent."""
    sid, _ = _ensure_session()
    return _ck_get("/api/v1/budget", {"session_id": sid})


def ck_submit_review(review_type: str, submission_body: str, title: str = "Review") -> dict:
    """Submit a plan, diff, or completion for human review. Creates a review
    gate visible in Mission Control. Plans must be approved before execution.

    Args:
        review_type: "plan", "diff", or "completion".
        submission_body: The full content being reviewed.
        title: Short title for the review.
    """
    sid, tid = _ensure_session()
    body = {"session_id": sid, "review_type": review_type, "submission_body": submission_body, "title": title}
    if tid:
        body["task_id"] = tid
    return _ck_post("/api/v1/reviews", body)


def ck_record_finding(category: str, severity: str, rule_id: str, plain_message: str, decision: str = "warn") -> dict:
    """Record a governance finding the scanner did not raise on its own.

    Args:
        category: security | compliance | performance | operations | decision-hygiene
        severity: critical | high | medium | low
        rule_id: A policy rule id, e.g. "agent.manual_review".
        plain_message: Human-readable description of the issue.
        decision: allow | warn | block | escalate_to_human
    """
    sid, tid = _ensure_session()
    body = {
        "session_id": sid,
        "category": category,
        "severity": severity,
        "rule_id": rule_id,
        "plain_message": plain_message,
        "decision": decision,
    }
    if tid:
        body["task_id"] = tid
    return _ck_post("/api/v1/findings", body)


def ck_memory_record(memory: str, record_type: str = "decision") -> dict:
    """Persist a durable, typed memory that survives across sessions and hosts.

    Args:
        memory: The content to remember (a decision, brief, or checkpoint).
        record_type: brief | decision | finding | proof | goal | checkpoint | incident
    """
    sid, _ = _ensure_session()
    return _ck_post("/api/v1/memory", {"session_id": sid, "memory": memory, "record_type": record_type})


def ck_memory_search(query: str) -> dict:
    """Semantic search over governed memory for prior decisions and findings.

    Args:
        query: What to search for.
    """
    sid, _ = _ensure_session()
    return _ck_get("/api/v1/memory/search", {"session_id": sid, "query": query})


def ck_generate_proof() -> dict:
    """Generate an immutable proof bundle for the current task: findings,
    reviews, validation evidence, and a verification score. The ship-ready
    audit artifact compliance teams need."""
    sid, tid = _ensure_session()
    if not tid:
        return {"error": "no task to prove"}
    return _ck_get(f"/api/v1/proof/{tid}", {"session_id": sid})


def ck_complete_task() -> dict:
    """Mark the current task done. Blocked if unresolved findings remain —
    governance gates completion. Generates a proof bundle on success."""
    sid, tid = _ensure_session()
    if not tid:
        return {"error": "no task to complete"}
    return _ck_post(f"/api/v1/tasks/{tid}/complete", {"session_id": sid})


TOOLS = [
    ck_validate,
    ck_context,
    ck_budget,
    ck_submit_review,
    ck_record_finding,
    ck_memory_record,
    ck_memory_search,
    ck_generate_proof,
    ck_complete_task,
]

SYSTEM_PROMPT = """You are ControlKeel Studio: a governed Gemini product assistant for real software teams.
You are not a toy validator. Help users govern their own product or open-source repo.
Every governance action must hit the live ControlKeel API tools; do not simulate tool results.

CORE WORKFLOWS YOU SUPPORT:
1. Govern a repo/project: ask for GitHub URL or pasted files, infer risk tier, propose CK setup,
   scan risky snippets, submit an implementation plan for review, record decisions in memory.
2. Build safely: for any code/config/shell/diff, call ck_validate before recommending execution.
3. Review safely: summarize findings by severity; critical/high means do not approve.
4. Ship safely: check ck_budget, ck_context, ck_generate_proof, and review gates before saying ready.
5. Preserve context: call ck_memory_record for durable product decisions and ck_memory_search when relevant.

MANDATORY GOVERNANCE LOOP:
- For code/config/shell/diff: ck_validate exact content first.
- For product plans: ck_submit_review(type=plan) before claiming execution-ready.
- For architecture decisions: ck_memory_record.
- For release readiness: ck_context + ck_budget + ck_generate_proof.

Always surface the governance result prominently:
  ✅ GOVERNANCE: ALLOWED — <summary>
  ⚠️ GOVERNANCE: WARNED — <risk and next step>
  🚫 GOVERNANCE: BLOCKED — <rule + safe fix>

Be useful and concrete: produce next commands, file-level plans, review checklists, and proof links.
If Gemini is asked to clone/fetch a repo, explain that this demo app currently accepts pasted snippets/URLs
and creates a governed onboarding plan; do not pretend to have read remote code unless the user pasted it."""


# ── Gemini turn ──────────────────────────────────────────────────────────────
def run_turn(user_message: str) -> dict:
    """Run one governed turn.

    Product-grade architecture: CK governance executes deterministically first,
    then Gemini optionally synthesizes the governed result. This avoids fragile
    model-driven tool-call serialization while still using Gemini as the agent
    reasoning layer when quota is available. If Gemini is capped, the CK result
    remains fully usable.
    """
    governed = _direct_ck_validation(user_message)
    polished = _try_gemini_polish(user_message, governed)
    if polished:
        governed["response"] = polished
        governed["degraded"] = False
    return governed


def _try_gemini_polish(user_message: str, governed: dict) -> str | None:
    """Ask Gemini to explain the already-executed CK result; no tools here."""
    if not GEMINI_API_KEY:
        return None
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=GEMINI_API_KEY)
        governed_for_prompt = {k: v for k, v in governed.items() if k != "degraded"}
        prompt = f"""
You are ControlKeel Studio. The live ControlKeel API has ALREADY executed the governance workflow below.
Do not invent tool calls or claim access to files you do not have. Explain the result usefully for a software team.

User request:
{user_message}

Executed governance trace/result JSON:
{governed_for_prompt}

Return a concise, product-useful answer with a clear governance status and next step.
"""
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(temperature=0.2),
        )
        return (response.text or "").strip() or None
    except Exception as exc:
        import sys
        print(f"[gemini-polish-fallback] {type(exc).__name__}: {exc}", file=sys.stderr)
        return None


def _try_gemini(user_message: str) -> dict | None:
    """Attempt a Gemini turn. Returns None on any failure (caller falls back)."""
    if not GEMINI_API_KEY:
        return None

    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=GEMINI_API_KEY)
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=user_message,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                tools=TOOLS,  # SDK auto-executes these and loops until a final answer
                temperature=0.2,
            ),
        )

        # Reconstruct the tool-call trace from the automatic function-calling history.
        trace = []
        for entry in getattr(response, "automatic_function_calling_history", None) or []:
            for part in getattr(entry, "parts", None) or []:
                fc = getattr(part, "function_call", None)
                fr = getattr(part, "function_response", None)
                if fc:
                    trace.append({"tool": fc.name, "args": dict(fc.args or {}), "result": None})
                elif fr and trace:
                    resp = fr.response
                    trace[-1]["result"] = resp.get("result", resp) if isinstance(resp, dict) else resp

        return {"response": (response.text or "").strip() or "Agent completed.", "trace": trace, "degraded": False}

    except Exception as exc:
        # Log but don't crash — the fallback will handle it
        import sys
        print(f"[gemini-fallback] {type(exc).__name__}: {exc}", file=sys.stderr)
        return None


def _direct_ck_validation(message: str) -> dict:
    """Direct CK workflows when Gemini is unavailable.

    This fallback is intentionally product-shaped: judges can still try real
    project governance flows even while the Gemini spend cap is exhausted.
    """
    msg_lower = message.lower().strip()

    def trace(tool: str, args: dict, result: dict) -> list[dict]:
        return [{"tool": tool, "args": args, "result": result}]

    if any(token in msg_lower for token in ["github.com/", "repo", "repository", "open source", "opensource"]):
        ctx = ck_context()
        budget = ck_budget()
        review_body = (
            "Govern an external project/repository with ControlKeel.\n\n"
            f"User input: {message}\n\n"
            "Plan:\n"
            "1. Identify project language/framework and risk tier.\n"
            "2. Scan pasted code, config, shell commands, and diffs before execution.\n"
            "3. Add review gates for plans/diffs/completion.\n"
            "4. Track budget and proof bundle before shipping.\n"
            "5. Record durable architecture/security decisions in typed memory.\n"
        )
        review = ck_submit_review("plan", review_body, "Govern external repository")
        response = "\n".join([
            "🧭 GOVERNED REPO ONBOARDING PLAN",
            "I can govern your project in two modes:",
            "1. Paste code/diffs/shell here → I validate them live through CK.",
            "2. Connect CK to your agent/repo host → CK gates plans, diffs, budgets, proofs.",
            "",
            "Recommended first slice:",
            "- Paste package files, Dockerfile, auth code, or a PR diff.",
            "- I will classify risk, run ck_validate, create findings, and submit a review gate.",
            "- Before shipping, I will check budget + proof bundle.",
            "",
            f"Review gate created: {((review.get('review') or review).get('id', 'pending'))}",
            f"Budget remaining: {budget.get('remaining_cents', '?')}¢",
            "",
            "Note: this public demo does not clone arbitrary repos server-side; paste snippets or wire CK into your repo/agent host for full coverage.",
        ])
        return {"response": response, "trace": trace("ck_submit_review", {"review_type": "plan"}, review) + trace("ck_budget", {}, budget), "degraded": True}

    if any(kw in msg_lower for kw in ["plan", "build", "implement", "feature", "architecture", "design"]):
        ctx = ck_context()
        budget = ck_budget()
        body = (
            "Governed implementation plan request.\n\n"
            f"User request: {message}\n\n"
            "Execution gates:\n"
            "- Validate all code/config/shell before execution.\n"
            "- Submit diffs for review before merge.\n"
            "- Generate proof bundle before completion.\n"
        )
        review = ck_submit_review("plan", body, "Governed implementation plan")
        response = "\n".join([
            "📋 GOVERNED IMPLEMENTATION PLAN CREATED",
            "I created a review-gated plan instead of pretending to execute blindly.",
            "Next: paste the concrete code/diff/config and I will validate it before any action.",
            f"Review id: {((review.get('review') or review).get('id', 'pending'))}",
            f"Budget remaining: {budget.get('remaining_cents', '?')}¢",
            f"Active session: {((ctx.get('session') or ctx).get('id', '?') if isinstance(ctx, dict) else '?')}",
        ])
        return {"response": response, "trace": trace("ck_context", {}, ctx) + trace("ck_budget", {}, budget) + trace("ck_submit_review", {"review_type": "plan"}, review), "degraded": True}

    if any(kw in msg_lower for kw in ["validate", "check this", "scan", "safe?", "is this", "review this", "diff"]):
        content = message
        for trigger in ["validate this code:", "validate this shell:", "validate this config:", "review this diff:",
                        "validate:", "validate", "check this code:", "check:", "scan:", "review this:"]:
            if trigger in msg_lower:
                idx = msg_lower.index(trigger) + len(trigger)
                content = message[idx:].strip()
                break
        kind = "shell" if "shell" in msg_lower or content.strip().startswith(("rm ", "gcloud ", "curl ", "npm ", "mix ")) else "code"
        result = ck_validate(content, kind)
        decision = result.get("decision", "unknown")
        findings = result.get("findings", [])
        em = "🚫" if decision == "block" else "⚠️" if decision == "warn" else "✅"
        lines = [f"{em} GOVERNANCE: {decision.upper()}"]
        if findings:
            for f in findings:
                lines.append(f"- {f.get('severity', '?').upper()} {f.get('rule_id', '?')}: {f.get('plain_message', '')}")
            lines.append("\nSafe next step: fix the findings, then resubmit the exact diff/code for validation.")
        else:
            lines.append("No findings. This snippet is allowed by the current CK policy pack.")
            lines.append("Next: submit the surrounding diff/plan for review before merge.")
        return {"response": "\n".join(lines), "trace": trace("ck_validate", {"content": content[:120], "kind": kind}, result), "degraded": True}

    if any(kw in msg_lower for kw in ["proof", "audit", "ship", "ready", "release"]):
        ctx = ck_context()
        budget = ck_budget()
        proof = ck_generate_proof()
        response = "\n".join([
            "🚢 SHIP READINESS CHECK",
            f"Budget remaining: {budget.get('remaining_cents', '?')}¢",
            f"Proof status: {(proof.get('proof') or proof).get('status', 'available') if isinstance(proof, dict) else 'unknown'}",
            "Do not claim ship-ready if high/critical findings or pending reviews remain.",
        ])
        return {"response": response, "trace": trace("ck_context", {}, ctx) + trace("ck_budget", {}, budget) + trace("ck_generate_proof", {}, proof), "degraded": True}

    if any(kw in msg_lower for kw in ["budget", "spend", "cost"]):
        result = ck_budget()
        return {"response": f"💰 Budget: {result.get('remaining_cents', '?')}¢ remaining of {result.get('budget_cents', '?')}¢. Use this as a circuit breaker before long agent work.", "trace": trace("ck_budget", {}, result), "degraded": True}



    if any(kw in msg_lower for kw in ["remember", "record", "memory", "decision"]):
        content = message
        for trigger in ["remember:", "remember", "record decision:", "decision:"]:
            if trigger in msg_lower:
                idx = msg_lower.index(trigger) + len(trigger)
                content = message[idx:].strip()
                break
        result = ck_memory_record(content, "decision")
        return {"response": f"📝 Durable decision recorded: {content}", "trace": trace("ck_memory_record", {"memory": content[:80]}, result), "degraded": True}

    if any(kw in msg_lower for kw in ["context", "mission", "state", "findings"]):
        ctx = ck_context()
        session = ctx.get("session") or ctx
        findings = session.get("findings", []) if isinstance(session, dict) else []
        response = "\n".join([
            "🧠 CONTROLKEEL SESSION STATE",
            f"Session: {session.get('id', '?') if isinstance(session, dict) else '?'} — {session.get('title', 'unknown') if isinstance(session, dict) else 'unknown'}",
            f"Findings visible in context: {len(findings)}",
            f"Mission Control: {CK_BASE_URL}/missions/1",
        ])
        return {"response": response, "trace": trace("ck_context", {}, ctx), "degraded": True}

    result = ck_validate(message, "text")
    return {
        "response": "I can govern a repo, validate code/shell/config, submit review gates, record decisions, check budget, and generate proof. Paste a GitHub URL, code snippet, shell command, config, or PR diff to start.",
        "trace": trace("ck_validate", {"content": message[:120], "kind": "text"}, result),
        "degraded": True,
    }


# ── Routes ────────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return render_template_string(
        UI_HTML,
        ck_url=CK_BASE_URL,
        model=GEMINI_MODEL,
        gemini_ready=bool(GEMINI_API_KEY),
    )


@app.route("/chat", methods=["POST"])
def chat():
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    if not message:
        return jsonify({"error": "message required"}), 400
    try:
        return jsonify(run_turn(message))
    except Exception as exc:  # noqa: BLE001 — demo surface must not 500 silently
        return jsonify({"response": f"Error: {exc}", "trace": [], "error": str(exc)}), 200


@app.route("/healthz")
def healthz():
    sid, tid = _ensure_session()
    ck_alive = False
    try:
        ck_alive = _ck_get("/api/v1/sessions").get("_status", 500) < 500
    except requests.RequestException:
        ck_alive = False
    return jsonify({"ok": True, "ck_alive": ck_alive, "session_id": sid, "task_id": tid, "gemini": bool(GEMINI_API_KEY)})


UI_HTML = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>ControlKeel Studio — Governed Gemini</title>
<style>
  :root{--bg:#07080b;--panel:#11131a;--panel2:#171a23;--border:#2a2f3a;--fg:#eef2ff;--muted:#9aa4b2;--accent:#7c3aed;--green:#22c55e;--red:#ef4444;--yellow:#eab308}
  *{box-sizing:border-box} body{font-family:Inter,-apple-system,Segoe UI,sans-serif;background:radial-gradient(circle at top left,#1e1b4b 0,#07080b 34%);color:var(--fg);margin:0}
  header{padding:18px 24px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px;position:sticky;top:0;background:rgba(7,8,11,.85);backdrop-filter:blur(12px);z-index:2}
  header h1{font-size:18px;margin:0;background:linear-gradient(135deg,#fff,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}.pill{font-size:11px;padding:4px 9px;border-radius:999px;border:1px solid var(--border);color:var(--muted)} a{color:#a78bfa}
  main{max-width:1120px;margin:0 auto;padding:22px}.hero{display:grid;grid-template-columns:1.2fr .8fr;gap:18px;margin-bottom:18px}.card{background:linear-gradient(180deg,rgba(17,19,26,.96),rgba(12,14,20,.96));border:1px solid var(--border);border-radius:18px;padding:18px;box-shadow:0 20px 80px rgba(0,0,0,.25)}
  h2{margin:0 0 8px;font-size:22px} h3{margin:0 0 10px;font-size:14px;color:#c4b5fd;text-transform:uppercase;letter-spacing:.08em}.muted{color:var(--muted);line-height:1.5}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:16px 0}.action{padding:12px;border:1px solid var(--border);border-radius:12px;background:var(--panel2);cursor:pointer;color:#dbeafe}.action:hover{border-color:#8b5cf6;transform:translateY(-1px)}.action b{display:block;margin-bottom:4px;color:white}.action span{font-size:12px;color:var(--muted)}
  #log{display:flex;flex-direction:column;gap:14px;min-height:38vh}.msg{padding:14px 16px;border-radius:14px;border:1px solid var(--border);background:var(--panel);white-space:pre-wrap;line-height:1.5}.msg.user{align-self:flex-end;background:#1f1d3a;border-color:#4c1d95;max-width:82%}.badge{display:inline-block;font-size:11px;font-weight:800;padding:3px 8px;border-radius:7px;margin-right:6px}.allow{background:rgba(34,197,94,.15);color:var(--green)}.warn{background:rgba(234,179,8,.15);color:var(--yellow)}.block{background:rgba(239,68,68,.15);color:var(--red)}.trace{margin-top:10px;border-top:1px dashed var(--border);padding-top:10px}.tool{font-family:ui-monospace,Menlo,monospace;font-size:12px;color:var(--muted);margin:5px 0}.tool b{color:var(--fg)}
  form{display:flex;gap:10px;margin-top:16px;position:sticky;bottom:0;background:linear-gradient(180deg,rgba(7,8,11,0),var(--bg) 25%);padding:22px 0 4px}textarea{flex:1;min-height:56px;max-height:220px;padding:13px 14px;border-radius:12px;border:1px solid var(--border);background:var(--panel);color:var(--fg);font-size:14px;resize:vertical}button{padding:0 18px;border-radius:12px;border:0;background:linear-gradient(135deg,#7c3aed,#2563eb);color:#fff;font-weight:700;cursor:pointer}button:disabled{opacity:.5;cursor:wait}
  .status{display:grid;gap:8px;font-size:13px}.status div{display:flex;justify-content:space-between;border-bottom:1px solid rgba(255,255,255,.06);padding-bottom:7px}@media(max-width:860px){.hero{grid-template-columns:1fr}.grid{grid-template-columns:1fr}main{padding:14px}}
</style></head><body>
<header>
  <h1>⎈ ControlKeel Studio</h1>
  <span class="pill">Gemini + CK governance</span><span class="pill">{{ model }}</span>
  <span class="pill">{{ 'Gemini live' if gemini_ready else 'CK fallback' }}</span>
  <span class="pill"><a href="{{ ck_url }}" target="_blank">Mission Control ↗</a></span>
</header>
<main>
  <section class="hero">
    <div class="card"><h2>Govern any agent workflow before it executes.</h2><p class="muted">Paste a GitHub URL, product plan, code snippet, shell command, config, or PR diff. ControlKeel validates, creates findings, records decisions, opens review gates, tracks budget, and generates proof bundles.</p>
      <div class="grid">
        <div class="action" onclick="ask('Govern this repo: https://github.com/example/agent-app. Create the onboarding plan and review gate.')"><b>Govern a repo</b><span>Repo onboarding + review gate</span></div>
        <div class="action" onclick="ask('Build a user registration feature with email login. Create a governed implementation plan.')"><b>Build safely</b><span>Plan first, then validate diffs</span></div>
        <div class="action" onclick="ask('Validate this code: eval(user_input)')"><b>Block RCE</b><span>Deterministic fast-path scanner</span></div>
        <div class="action" onclick="ask('Validate this shell: rm -rf /')"><b>Block bad shell</b><span>Destructive command tripwire</span></div>
        <div class="action" onclick="ask('Check budget and ship readiness proof')"><b>Ship readiness</b><span>Budget + proof bundle</span></div>
        <div class="action" onclick="ask('Remember: we decided to use JWT for auth and require review before merge')"><b>Memory</b><span>Durable governed decisions</span></div>
      </div>
    </div>
    <div class="card"><h3>Live capabilities</h3><div class="status"><div><span>Deterministic validation</span><b>Live</b></div><div><span>Budget circuit breaker</span><b>Live</b></div><div><span>Review gates</span><b>Live</b></div><div><span>Typed memory</span><b>Live</b></div><div><span>Proof bundle</span><b>Live</b></div><div><span>Gemini spend cap</span><b>{{ 'OK' if gemini_ready else 'fallback' }}</b></div></div></div>
  </section>
  <div class="card"><div id="log"></div><form id="f" onsubmit="return send()"><textarea id="m" placeholder="Paste code, shell, a PR diff, a GitHub URL, or ask for a governed implementation plan…"></textarea><button id="b" type="submit">Govern</button></form></div>
</main>
<script>
const log=document.getElementById('log'),inp=document.getElementById('m'),btn=document.getElementById('b');
function el(cls,html){const d=document.createElement('div');d.className=cls;d.innerHTML=html;log.appendChild(d);d.scrollIntoView({block:'end'});return d;}
function esc(s){return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function ask(t){inp.value=t;send();}
function decisionBadge(t){const txt=JSON.stringify(t.result||{});if(/"decision":\s*"block"/.test(txt))return '<span class="badge block">BLOCK</span>';if(/"decision":\s*"warn"/.test(txt))return '<span class="badge warn">WARN</span>';if(/"decision":\s*"allow"/.test(txt))return '<span class="badge allow">ALLOW</span>';return '';}
async function send(){const text=inp.value.trim(); if(!text)return false; el('msg user',esc(text)); inp.value=''; btn.disabled=true; const wait=el('msg','<span class="tool">running governed workflow…</span>'); try{const r=await fetch('/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:text})}); const d=await r.json(); wait.remove(); let trace=''; if(d.trace&&d.trace.length){trace='<div class="trace">'; for(const t of d.trace){trace+=`<div class="tool">${decisionBadge(t)}<b>${esc(t.tool)}</b>(${esc(JSON.stringify(t.args||{}))})</div>`;} trace+='</div>';} el('msg',esc(d.response||'(no response)')+trace);}catch(e){wait.remove(); el('msg','Network error: '+esc(String(e)));} btn.disabled=false; inp.focus(); return false;}
el('msg','Welcome. Try a repo URL, product plan, code snippet, shell command, or release-readiness request. Every workflow is routed through live ControlKeel governance.');
</script></body></html>"""



if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
