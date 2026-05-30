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

SYSTEM_PROMPT = """You are a governed Gemini agent powered by ControlKeel — a real, \
hosted governance platform. Every tool you call hits a live ControlKeel API; this is \
not a simulation.

MANDATORY LOOP for every request that involves code, config, or shell:
1. Call ck_validate on the exact content BEFORE doing anything with it.
2. Read the decision:
   - allow -> proceed; you may call ck_generate_proof for an audit trail.
   - warn  -> state the risk plainly and ask the user to confirm.
   - block -> DO NOT proceed. Explain the finding and suggest the fix.
3. Use ck_submit_review for plans, ck_memory_record for decisions, ck_budget to check spend.

Always surface the governance decision prominently in your reply:
  ✅ GOVERNANCE: ALLOWED — <summary>
  ⚠️ GOVERNANCE: WARNED — <findings>
  🚫 GOVERNANCE: BLOCKED — <findings> — <suggested fix>

Be concise and technical. You are demoing to VCs and AI researchers — show the \
governance working, do not just describe it."""


# ── Gemini turn ──────────────────────────────────────────────────────────────
def run_turn(user_message: str) -> dict:
    """Run one Gemini turn with automatic function calling against live CK."""
    if not GEMINI_API_KEY:
        # Graceful degradation: no Gemini key -> still prove CK is live by
        # validating the message directly, so the demo never hard-fails.
        result = ck_validate(user_message, "text")
        decision = result.get("decision", "unknown")
        return {
            "response": f"(No GEMINI_API_KEY set — direct CK validation shown.) Decision: {decision}",
            "trace": [{"tool": "ck_validate", "args": {"content": user_message[:120], "kind": "text"}, "result": result}],
            "degraded": True,
        }

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
                # google-genai wraps function results as {"result": <value>}
                trace[-1]["result"] = resp.get("result", resp) if isinstance(resp, dict) else resp

    return {"response": (response.text or "").strip() or "Agent completed.", "trace": trace, "degraded": False}


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
<title>ControlKeel × Gemini — Governed Agent</title>
<style>
  :root{--bg:#0a0a0b;--panel:#141416;--border:#2a2a2e;--fg:#e8e8ec;--muted:#9a9aa2;--accent:#6366f1}
  *{box-sizing:border-box}
  body{font-family:Inter,-apple-system,Segoe UI,sans-serif;background:var(--bg);color:var(--fg);margin:0}
  header{padding:18px 24px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:12px}
  header h1{font-size:18px;margin:0;background:linear-gradient(135deg,#e8e8ec,#6366f1);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
  .pill{font-size:11px;padding:3px 9px;border-radius:999px;border:1px solid var(--border);color:var(--muted)}
  main{max-width:860px;margin:0 auto;padding:20px}
  #log{display:flex;flex-direction:column;gap:14px;min-height:50vh}
  .msg{padding:12px 14px;border-radius:12px;border:1px solid var(--border);background:var(--panel);white-space:pre-wrap;line-height:1.5}
  .msg.user{align-self:flex-end;background:#1c1c33;border-color:#33335a;max-width:80%}
  .badge{display:inline-block;font-size:11px;font-weight:700;padding:2px 8px;border-radius:6px;margin-right:6px}
  .allow{background:rgba(34,197,94,.15);color:#22c55e}.warn{background:rgba(234,179,8,.15);color:#eab308}
  .block{background:rgba(239,68,68,.15);color:#ef4444}
  .trace{margin-top:10px;border-top:1px dashed var(--border);padding-top:10px}
  .tool{font-family:ui-monospace,Menlo,monospace;font-size:12px;color:var(--muted);margin:4px 0}
  .tool b{color:var(--fg)}
  form{display:flex;gap:10px;margin-top:18px;position:sticky;bottom:0;background:var(--bg);padding:12px 0}
  input{flex:1;padding:12px 14px;border-radius:10px;border:1px solid var(--border);background:var(--panel);color:var(--fg);font-size:15px}
  button{padding:12px 18px;border-radius:10px;border:0;background:var(--accent);color:#fff;font-weight:600;cursor:pointer}
  button:disabled{opacity:.5;cursor:wait}
  .chips{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px}
  .chip{font-size:12px;padding:6px 10px;border-radius:8px;border:1px solid var(--border);color:var(--muted);cursor:pointer}
  .chip:hover{border-color:var(--accent);color:var(--fg)}
  a{color:var(--accent)}
</style></head><body>
<header>
  <h1>⎈ ControlKeel × Gemini</h1>
  <span class="pill">{{ model }}</span>
  <span class="pill">{{ 'Gemini live' if gemini_ready else 'CK-only mode' }}</span>
  <span class="pill"><a href="{{ ck_url }}" target="_blank">Mission Control ↗</a></span>
</header>
<main>
  <div class="chips">
    <span class="chip" onclick="ask(this)">Validate this code: eval(user_input)</span>
    <span class="chip" onclick="ask(this)">Validate: api_key = 'sk-proj-abc123def456ghi789'</span>
    <span class="chip" onclick="ask(this)">Validate this shell: rm -rf /</span>
    <span class="chip" onclick="ask(this)">Validate this code: def health(): return {'status':'ok'}</span>
    <span class="chip" onclick="ask(this)">Check the budget</span>
    <span class="chip" onclick="ask(this)">Remember: we decided to use JWT for auth</span>
  </div>
  <div id="log"></div>
  <form id="f" onsubmit="return send()">
    <input id="m" placeholder="Ask the governed agent to build or validate something…" autocomplete="off"/>
    <button id="b" type="submit">Send</button>
  </form>
</main>
<script>
const log=document.getElementById('log'),inp=document.getElementById('m'),btn=document.getElementById('b');
function el(cls,html){const d=document.createElement('div');d.className=cls;d.innerHTML=html;log.appendChild(d);log.scrollIntoView({block:'end'});return d;}
function esc(s){return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function ask(c){inp.value=c.textContent;send();}
function decisionBadge(t){
  const txt=JSON.stringify(t.result||{});
  if(/"decision":\\s*"block"/.test(txt))return '<span class="badge block">BLOCK</span>';
  if(/"decision":\\s*"warn"/.test(txt))return '<span class="badge warn">WARN</span>';
  if(/"decision":\\s*"allow"/.test(txt))return '<span class="badge allow">ALLOW</span>';
  return '';
}
async function send(){
  const text=inp.value.trim(); if(!text)return false;
  el('msg user',esc(text)); inp.value=''; btn.disabled=true;
  const wait=el('msg','<span class="tool">running governed turn…</span>');
  try{
    const r=await fetch('/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({message:text})});
    const d=await r.json(); wait.remove();
    let trace='';
    if(d.trace&&d.trace.length){
      trace='<div class="trace">';
      for(const t of d.trace){trace+=`<div class="tool">${decisionBadge(t)}<b>${esc(t.tool)}</b>(${esc(JSON.stringify(t.args||{}))})</div>`;}
      trace+='</div>';
    }
    el('msg',esc(d.response||'(no response)')+trace);
  }catch(e){wait.remove(); el('msg','Network error: '+esc(String(e)));}
  btn.disabled=false; inp.focus(); return false;
}
</script>
</body></html>"""


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
