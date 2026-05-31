"""
ControlKeel Studio — Governed Gemini Agent (Cloud Run)
=======================================================
A real governed-agent product, not a demo template.

Users can:
  - Paste a GitHub URL → get a real governance onboarding plan with fetched repo context
  - Paste code / shell / config / diffs → validated live through CK's deterministic scanner
  - Ask Gemini to build/plan a feature → governed implementation plan with review gate
  - Check budget, findings, proof readiness before shipping
  - Record durable architecture decisions in typed CK memory

Primary execution path: Gemini 2.5 Flash with automatic function calling hits the live
ControlKeel API. Each tool call (ck_validate, ck_submit_review, etc.) executes in real
Python code and returns real CK results — this is not a simulation.

Fallback path: when Gemini is rate-limited or unavailable, direct CK workflows still run.

Routes:
  GET  /          main chat UI
  POST /chat      { message, history? } → { response, trace, degraded }
  GET  /health    liveness (also /healthz/)
"""

from __future__ import annotations

import os
import re
import sys

import requests
from flask import Flask, jsonify, render_template_string, request

# ── Config ──────────────────────────────────────────────────────────────────
CK_BASE_URL = os.environ.get("CK_BASE_URL", "https://controlkeel-834811228927.us-central1.run.app").rstrip("/")
CK_API_KEY  = os.environ.get("CK_API_KEY", "").strip()
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
GEMINI_MODEL   = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")

_STATE: dict = {"session_id": None, "task_id": None}
app = Flask(__name__)


# ── CK HTTP client ───────────────────────────────────────────────────────────
def _ck_headers() -> dict:
    h = {"Content-Type": "application/json"}
    if CK_API_KEY:
        h["Authorization"] = f"Bearer {CK_API_KEY}"
    return h

def _ck_get(path: str, params: dict | None = None) -> dict:
    try:
        r = requests.get(f"{CK_BASE_URL}{path}", headers=_ck_headers(), params=params, timeout=30)
        return _as_json(r)
    except Exception as e:
        return {"error": str(e)}

def _ck_post(path: str, body: dict | None = None) -> dict:
    try:
        r = requests.post(f"{CK_BASE_URL}{path}", headers=_ck_headers(), json=body or {}, timeout=30)
        return _as_json(r)
    except Exception as e:
        return {"error": str(e)}

def _as_json(r: requests.Response) -> dict:
    try:
        data = r.json()
    except ValueError:
        return {"_status": r.status_code, "_body": r.text[:300]}
    if isinstance(data, dict):
        data.setdefault("_status", r.status_code)
    return data if isinstance(data, dict) else {"_status": r.status_code, "data": data}


# ── Session bootstrap ────────────────────────────────────────────────────────
def _ensure_session() -> tuple:
    if _STATE["session_id"]:
        return _STATE["session_id"], _STATE["task_id"]

    if os.environ.get("CK_SESSION_ID"):
        _STATE["session_id"] = int(os.environ["CK_SESSION_ID"])
        if os.environ.get("CK_TASK_ID"):
            _STATE["task_id"] = int(os.environ["CK_TASK_ID"])
        return _STATE["session_id"], _STATE["task_id"]

    booted = _ck_post("/api/v1/bootstrap", {"project_name": "ck-studio", "agent": "gemini"})
    session = booted.get("session") or booted
    _STATE["session_id"] = session.get("id") if isinstance(session, dict) else None

    sid = _STATE["session_id"]
    if sid and not _STATE["task_id"]:
        detail = _ck_get(f"/api/v1/sessions/{sid}")
        tasks = (detail.get("session") or detail).get("tasks") or []
        if tasks:
            active = next((t for t in tasks if t.get("status") in ("in_progress", "queued")), tasks[0])
            _STATE["task_id"] = active.get("id")
    return _STATE["session_id"], _STATE["task_id"]


# ── GitHub repo context fetcher ──────────────────────────────────────────────
_GITHUB_RE = re.compile(r"github\.com/([^/\s]+)/([^/\s]+)")

def _fetch_github_context(url: str) -> str:
    """
    Fetch README, package.json, pyproject.toml, Dockerfile, and any .env.example
    from a public GitHub repo. Returns a formatted summary to pass to Gemini/CK.
    """
    m = _GITHUB_RE.search(url)
    if not m:
        return f"Could not parse GitHub URL: {url}"
    owner, repo = m.group(1), m.group(2).rstrip("/").split("/")[0]

    # Try main then master branch
    candidates = [
        "README.md", "package.json", "pyproject.toml", "requirements.txt",
        "Dockerfile", "docker-compose.yml", ".env.example", "go.mod",
        "Cargo.toml", "pom.xml", "build.gradle",
    ]
    fetched = {}
    for branch in ("main", "master"):
        for fname in candidates:
            if fname in fetched:
                continue
            raw = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{fname}"
            try:
                r = requests.get(raw, timeout=10)
                if r.status_code == 200 and r.text:
                    # Truncate large files — we only need enough for risk classification
                    fetched[fname] = r.text[:3000]
            except Exception:
                pass
        if fetched:
            break

    if not fetched:
        return f"Could not fetch any files from {owner}/{repo}. The repo may be private or not exist."

    lines = [f"## GitHub repo: {owner}/{repo}", f"URL: {url}", ""]
    for fname, content in fetched.items():
        lines.append(f"### {fname}")
        lines.append("```")
        lines.append(content)
        lines.append("```")
        lines.append("")
    return "\n".join(lines)


# ── CK governance tools (auto-executed by google-genai SDK) ─────────────────
# These are passed to Gemini as TOOLS. The SDK detects function calls in the
# model response and executes the matching Python function automatically,
# feeding the result back without any manual intervention.

def ck_validate(content: str, kind: str = "code") -> dict:
    """Validate code, config, a shell command, or text against ControlKeel's
    6-layer deterministic scanner. Catches RCE (eval/exec), hardcoded secrets,
    SQL injection, destructive shell, PII exposure, and 12+ more patterns.
    Runs in ~50ms with zero LLM tokens. Call this BEFORE any code execution.

    Returns {decision: allow|warn|block, findings: [{severity, rule_id, plain_message}]}.

    Args:
        content: Exact code/config/shell/text to scan.
        kind: "code", "config", "shell", or "text".
    """
    return _ck_post("/api/v1/validate", {"content": content, "kind": kind, "source_type": "generated"})


def ck_validate_github_repo(github_url: str) -> dict:
    """Fetch the key files (README, Dockerfile, package.json, etc.) from a public
    GitHub repository and run ControlKeel governance analysis on the project.
    Returns a structured risk assessment with findings and recommended CK setup.

    Args:
        github_url: Full GitHub URL, e.g. https://github.com/owner/repo
    """
    context = _fetch_github_context(github_url)
    if "Could not" in context and len(context) < 200:
        return {"error": context, "github_url": github_url}

    # Run a single combined scan on the full context
    result = _ck_post("/api/v1/validate", {
        "content": context[:8000],
        "kind": "code",
        "source_type": "repository",
    })
    result["github_url"] = github_url
    result["fetched_context_preview"] = context[:500]
    return result


def ck_context() -> dict:
    """Load governed session state: active findings, budget, tasks, proof summary.
    Call at the start of a task or when the user asks about current posture."""
    sid, _ = _ensure_session()
    if not sid:
        return {"error": "no session — CK may be starting up"}
    return _ck_get(f"/api/v1/sessions/{sid}")


def ck_budget() -> dict:
    """Check remaining budget and spend. CK tracks per-invocation cost with a
    circuit breaker — when the budget is spent, agents cannot keep burning money."""
    sid, _ = _ensure_session()
    return _ck_get("/api/v1/budget", {"session_id": sid})


def ck_submit_review(review_type: str, submission_body: str, title: str = "Review") -> dict:
    """Submit a plan, diff, or completion for human review. Creates a review gate
    visible in Mission Control. Use this before claiming a plan is execution-ready.

    Args:
        review_type: "plan", "diff", or "completion".
        submission_body: Full content being reviewed (plan text, diff, etc.).
        title: Short title shown in Mission Control.
    """
    sid, tid = _ensure_session()
    body = {"session_id": sid, "review_type": review_type, "submission_body": submission_body, "title": title}
    if tid:
        body["task_id"] = tid
    return _ck_post("/api/v1/reviews", body)


def ck_record_finding(category: str, severity: str, rule_id: str, plain_message: str, decision: str = "warn") -> dict:
    """Record a governance finding the automatic scanner did not raise.

    Args:
        category: security | compliance | performance | operations | decision-hygiene
        severity: critical | high | medium | low
        rule_id: Policy rule identifier, e.g. "security.missing_auth".
        plain_message: Human-readable description of the issue.
        decision: allow | warn | block | escalate_to_human
    """
    sid, tid = _ensure_session()
    body = {"session_id": sid, "category": category, "severity": severity,
            "rule_id": rule_id, "plain_message": plain_message, "decision": decision}
    if tid:
        body["task_id"] = tid
    return _ck_post("/api/v1/findings", body)


def ck_memory_record(memory: str, record_type: str = "decision") -> dict:
    """Persist a durable, typed memory that survives sessions, restarts, and host switches.
    Use for architecture decisions, security posture choices, and product direction.

    Args:
        memory: Content to remember — a decision, brief, goal, or checkpoint.
        record_type: brief | decision | finding | proof | goal | checkpoint | incident
    """
    sid, _ = _ensure_session()
    return _ck_post("/api/v1/memory", {"session_id": sid, "memory": memory, "record_type": record_type})


def ck_memory_search(query: str) -> dict:
    """Search governed memory for prior decisions and findings using semantic search.

    Args:
        query: What to search for, e.g. "auth decisions" or "security findings".
    """
    sid, _ = _ensure_session()
    return _ck_get("/api/v1/memory/search", {"session_id": sid, "query": query})


def ck_generate_proof() -> dict:
    """Generate an immutable proof bundle for the current task: all findings,
    reviews, validation results, and a verification score. The artifact
    compliance teams need for SOC 2 / GDPR sign-off on agent-generated work."""
    sid, tid = _ensure_session()
    if not tid:
        return {"error": "no active task — start a task first"}
    return _ck_get(f"/api/v1/proof/{tid}", {"session_id": sid})


def ck_complete_task() -> dict:
    """Mark the current task done. Will be BLOCKED if critical/high findings
    remain unresolved — governance gates completion. Generates a proof bundle."""
    sid, tid = _ensure_session()
    if not tid:
        return {"error": "no active task to complete"}
    return _ck_post(f"/api/v1/tasks/{tid}/complete", {"session_id": sid})


def ck_platform_overview() -> dict:
    """Return a compact cross-platform snapshot: mission state, budget, findings,
    proofs, benchmarks, policies, providers, skills, and key Mission Control URLs."""
    sid, _ = _ensure_session()
    return {
        "session": _ck_get(f"/api/v1/sessions/{sid}") if sid else {"error": "no session"},
        "budget": ck_budget(),
        "findings": _ck_get("/api/v1/findings", {"session_id": sid}) if sid else {},
        "proofs": _ck_get("/api/v1/proofs", {"session_id": sid}) if sid else {},
        "benchmarks": _ck_get("/api/v1/benchmarks"),
        "policies": _ck_get("/api/v1/policies"),
        "providers": _ck_get("/api/v1/providers/status"),
        "skills": _ck_get("/api/v1/skills"),
        "urls": {
            "mission_control": f"{CK_BASE_URL}/missions/1",
            "observability": f"{CK_BASE_URL}/observability",
            "policies": f"{CK_BASE_URL}/policies",
            "benchmarks": f"{CK_BASE_URL}/benchmarks",
            "ship": f"{CK_BASE_URL}/ship",
            "proofs": f"{CK_BASE_URL}/proofs",
            "findings": f"{CK_BASE_URL}/findings",
            "skills": f"{CK_BASE_URL}/skills",
            "deploy": f"{CK_BASE_URL}/deploy",
        },
    }


def ck_observability_summary() -> dict:
    """Return observability and continuous-improvement signals: improvement loop,
    audit log, task graph, provider health, and observability URLs."""
    sid, _ = _ensure_session()
    return {
        "improvement": _ck_get("/api/v1/improvement", {"session_id": sid}),
        "audit_log": _ck_get(f"/api/v1/sessions/{sid}/audit-log", {"limit": 20}) if sid else {},
        "graph": _ck_get(f"/api/v1/sessions/{sid}/graph") if sid else {},
        "provider_status": _ck_get("/api/v1/providers/status"),
        "urls": {
            "overview": f"{CK_BASE_URL}/observability",
            "loop": f"{CK_BASE_URL}/observability/loop",
            "costs": f"{CK_BASE_URL}/observability/costs",
            "trends": f"{CK_BASE_URL}/observability/trends",
            "regressions": f"{CK_BASE_URL}/observability/regressions",
            "recommendations": f"{CK_BASE_URL}/observability/recommendations",
        },
    }


def ck_policy_summary() -> dict:
    """Return active policy surfaces: policy packs, domains, workspace tool policy,
    and policy studio URLs."""
    sid, _ = _ensure_session()
    session = (ck_context().get("session") or {}) if sid else {}
    workspace = session.get("workspace") or {}
    workspace_id = workspace.get("id") or session.get("workspace_id")
    return {
        "domains": _ck_get("/api/v1/domains"),
        "policies": _ck_get("/api/v1/policies"),
        "workspace_policy_sets": _ck_get(f"/api/v1/workspaces/{workspace_id}/policy-sets") if workspace_id else {},
        "tool_policy": _ck_get(f"/api/v1/workspaces/{workspace_id}/tool-policy") if workspace_id else {},
        "urls": {
            "policy_studio": f"{CK_BASE_URL}/policies",
            "tool_policy": f"{CK_BASE_URL}/workspaces/{workspace_id}/tool-policy" if workspace_id else f"{CK_BASE_URL}/policies",
        },
    }


def ck_learning_summary(query: str = "architecture decisions security findings governance memory") -> dict:
    """Return typed memory and self-learning surfaces: semantic memory hits,
    session context, and memory quality observability URL."""
    return {
        "memory_hits": ck_memory_search(query),
        "context": ck_context(),
        "urls": {
            "memory_quality": f"{CK_BASE_URL}/observability/memory-quality",
            "session_memory": f"{CK_BASE_URL}/observability/sessions/1/memory",
        },
    }


def ck_benchmark_summary() -> dict:
    """Return benchmark/eval/regression surfaces and URLs."""
    return {
        "benchmarks": _ck_get("/api/v1/benchmarks"),
        "urls": {
            "benchmarks": f"{CK_BASE_URL}/benchmarks",
            "history": f"{CK_BASE_URL}/observability/benchmarks/history",
            "scenarios": f"{CK_BASE_URL}/observability/benchmarks/scenarios",
            "evals": f"{CK_BASE_URL}/observability/evals",
            "regressions": f"{CK_BASE_URL}/observability/regressions",
            "promotions": f"{CK_BASE_URL}/observability/promotions",
        },
    }


def ck_integration_summary() -> dict:
    """Return host/skill/deploy integration surfaces."""
    return {
        "agents": _ck_get("/api/v1/agents"),
        "skills": _ck_get("/api/v1/skills"),
        "providers": _ck_get("/api/v1/providers"),
        "provider_status": _ck_get("/api/v1/providers/status"),
        "urls": {
            "install": f"{CK_BASE_URL}/install",
            "skills": f"{CK_BASE_URL}/skills",
            "deploy": f"{CK_BASE_URL}/deploy",
            "providers": f"{CK_BASE_URL}/observability/costs",
        },
    }


TOOLS = [
    ck_validate,
    ck_validate_github_repo,
    ck_context,
    ck_budget,
    ck_submit_review,
    ck_record_finding,
    ck_memory_record,
    ck_memory_search,
    ck_generate_proof,
    ck_complete_task,
    ck_platform_overview,
    ck_observability_summary,
    ck_policy_summary,
    ck_learning_summary,
    ck_benchmark_summary,
    ck_integration_summary,
]

SYSTEM_PROMPT = f"""You are **ControlKeel Studio** — a governed Gemini product assistant for real software teams.
You help users govern their own project, open-source repo, or agent workflow using the live ControlKeel platform.
This is a real product. Every tool call executes against the hosted ControlKeel API at {CK_BASE_URL}.

## What you can actually do

1. **Govern a GitHub repo** — call `ck_validate_github_repo(url)` which fetches the real files and runs CK analysis.
2. **Validate code/config/shell** — call `ck_validate(content, kind)` before recommending any execution.
3. **Build safely** — create implementation plans with `ck_submit_review(type="plan", ...)`.
4. **Record decisions** — `ck_memory_record(memory, record_type)` for durable cross-session context.
5. **Ship safely** — `ck_context()`, `ck_budget()`, `ck_generate_proof()` before release.
6. **Observe and improve** — `ck_observability_summary()` for audit log, improvement loop, costs, trends, regressions.
7. **Operate policies** — `ck_policy_summary()` for policy packs, domain controls, workspace tool policy.
8. **Learn continuously** — `ck_learning_summary(query)` for typed memory, prior decisions, memory quality.
9. **Benchmark/evaluate** — `ck_benchmark_summary()` for suites, evals, regressions, promotions.
10. **Integrate/deploy** — `ck_integration_summary()` for agents, skills, providers, install and deploy surfaces.

## Mandatory governance loop

For every code/config/shell/diff request:
1. Call `ck_validate` on the exact content — BEFORE recommending execution.
2. For plans or diffs: call `ck_submit_review` — create a review gate.
3. For decisions: call `ck_memory_record` — persist durably.
4. For release: call `ck_context` + `ck_budget` + `ck_generate_proof`.

## STRICT governance response rule

When `ck_validate` returns `decision`, you MUST use the matching label — no exceptions:
- `"block"` → start with **🚫 GOVERNANCE: BLOCKED** — do NOT proceed; show rule_id + plain_message + exact safe fix
- `"warn"`  → start with **⚠️ GOVERNANCE: WARNED** — explain risk, ask confirmation
- `"allow"` → start with **✅ GOVERNANCE: ALLOWED** — safe to proceed

Never use WARNED for a block decision. Never use BLOCKED for an allow decision.
The `decision` field in the tool result is the ground truth — always honour it.

## Tone

Be concrete and useful. Give commands, file-level plans, and next steps — not just descriptions.
When the user pastes code or a repo URL, do real work: validate it, classify the risk, create findings, propose the next governed step.
Do not pretend to clone repos server-side — use `ck_validate_github_repo` to fetch and analyse.
"""


# ── Primary execution: Gemini with automatic function calling ────────────────
def _try_gemini(user_message: str, history: list[dict] | None = None) -> dict | None:
    """
    Primary path: Gemini 2.5 Flash with auto function calling.

    The google-genai SDK automatically executes the Python functions in TOOLS
    when Gemini returns a functionCall, then feeds the result back and loops
    until Gemini produces a final text response. Every tool call hits the live
    ControlKeel API — no mocking.
    """
    if not GEMINI_API_KEY:
        return None
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=GEMINI_API_KEY)

        # Build contents: system sets context, history replays prior turns,
        # then append the new user message.
        contents = []
        for turn in (history or []):
            role = "user" if turn.get("role") == "user" else "model"
            contents.append(types.Content(role=role, parts=[types.Part(text=turn.get("content", ""))]))
        contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))

        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                tools=TOOLS,
                temperature=0.2,
            ),
        )

        # Extract tool-call trace from automatic function calling history.
        # In google-genai >=1.20, fr.response is a protobuf MapComposite/Struct,
        # not a plain dict — convert explicitly so .get() and JSON serialisation work.
        trace = []
        for entry in getattr(response, "automatic_function_calling_history", None) or []:
            for part in getattr(entry, "parts", None) or []:
                fc = getattr(part, "function_call", None)
                fr = getattr(part, "function_response", None)
                if fc:
                    trace.append({"tool": fc.name, "args": dict(fc.args or {}), "result": None})
                elif fr and trace:
                    raw = fr.response
                    # Convert protobuf MapComposite / Struct to a plain Python dict
                    try:
                        resp = dict(raw) if not isinstance(raw, dict) and hasattr(raw, "items") else (raw if isinstance(raw, dict) else {})
                    except Exception:
                        resp = {}
                    # SDK wraps function results as {"result": <value>} in some versions
                    trace[-1]["result"] = resp.get("result", resp) if "result" in resp else resp

        text = (response.text or "").strip()
        return {"response": text or "Governance workflow complete.", "trace": trace, "degraded": False}

    except Exception as exc:
        print(f"[gemini] {type(exc).__name__}: {exc}", file=sys.stderr)
        return None


# ── Fallback: direct CK workflows (no Gemini needed) ────────────────────────
def _direct_ck(message: str) -> dict:
    """
    Fallback when Gemini is unavailable or rate-limited.
    Runs real CK governance workflows based on message intent.
    The result is a real governance output — not simulated.
    """
    msg = message.lower().strip()

    def tr(tool, args, result):
        return [{"tool": tool, "args": args, "result": result}]

    # GitHub repo
    github_match = _GITHUB_RE.search(message)
    if github_match or any(kw in msg for kw in ["github.com/", "repository", "open source", "opensource", "govern this repo"]):
        url = f"https://github.com/{github_match.group(1)}/{github_match.group(2)}" if github_match else message
        ctx = ck_context()
        repo_result = ck_validate_github_repo(url)
        decision = repo_result.get("decision", "unknown")
        findings = repo_result.get("findings", [])
        review = ck_submit_review("plan", f"Govern repo: {url}\n\nRisk classification: {decision}\nFindings: {len(findings)}", f"Repo governance: {url[:60]}")
        lines = [
            f"🧭 **REPO GOVERNANCE ANALYSIS: {url}**",
            f"CK scan decision: **{decision.upper()}**",
            f"Findings: {len(findings)}",
        ]
        if findings:
            for f in findings[:5]:
                sev = f.get("severity", "?")
                lines.append(f"  - {sev.upper()} — {f.get('plain_message', f.get('rule_id', ''))}")
        lines += [
            "",
            "**Review gate created.** Approve in Mission Control before proceeding.",
            "**Next steps:**",
            "1. Paste Dockerfile, auth code, or a PR diff — I'll validate it live.",
            "2. Run `ck_validate` on any generated code before execution.",
            "3. Check budget + generate proof before claiming ship-ready.",
            "",
            f"[Open Mission Control]({CK_BASE_URL}/missions/1) — [Findings]({CK_BASE_URL}/findings)",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_validate_github_repo", {"github_url": url}, repo_result) + tr("ck_submit_review", {"review_type": "plan"}, review), "degraded": True}

    # Explicit validation request or code snippet
    if any(kw in msg for kw in ["validate", "check this", "scan", "is this safe", "review this", "diff"]) or \
       any(s in message for s in ["def ", "function ", "import ", "require(", "SELECT ", "rm -rf", "eval(", "exec("]):
        content = message
        for trigger in ["validate this code:", "validate this shell:", "validate this config:",
                        "validate:", "check this:", "scan:", "review this diff:"]:
            if trigger in msg:
                content = message[msg.index(trigger) + len(trigger):].strip()
                break
        kind = "shell" if any(s in content for s in ["rm ", "gcloud ", "kubectl ", "npm run", "curl ", "$ "]) else "code"
        result = ck_validate(content, kind)
        decision = result.get("decision", "unknown")
        findings = result.get("findings", [])
        em = {"block": "🚫", "warn": "⚠️", "allow": "✅"}.get(decision, "🔍")
        lines = [f"{em} **GOVERNANCE: {decision.upper()}**"]
        if findings:
            for f in findings:
                lines.append(f"- **{f.get('severity','?').upper()}** `{f.get('rule_id','?')}`: {f.get('plain_message','')}")
            lines.append("\n**Safe fix:** Address the findings above, then paste the corrected version.")
            lines.append(f"[See findings in Mission Control]({CK_BASE_URL}/findings)")
        else:
            lines.append("No issues found. Snippet passes CK policy.")
            lines.append("Next: paste the surrounding diff for a full review gate before merge.")
        return {"response": "\n".join(lines), "trace": tr("ck_validate", {"content": content[:120], "kind": kind}, result), "degraded": True}

    # Platform / observability / policies / learning / integrations
    if any(kw in msg for kw in ["platform overview", "all features", "everything", "full platform", "what can controlkeel do"]):
        result = ck_platform_overview()
        urls = result.get("urls", {})
        lines = [
            "🧭 **CONTROLKEEL PLATFORM OVERVIEW**",
            "ControlKeel is more than validation: it is the control plane for agent-built software.",
            "",
            "**Live surfaces:**",
            f"- Mission Control: {urls.get('mission_control')}",
            f"- Observability: {urls.get('observability')}",
            f"- Policy Studio: {urls.get('policies')}",
            f"- Benchmarks/Evals: {urls.get('benchmarks')}",
            f"- Ship Readiness: {urls.get('ship')}",
            f"- Proof Bundles: {urls.get('proofs')}",
            f"- Skills/Integrations: {urls.get('skills')}",
            "",
            "Ask for: observability, policies, self-learning memory, benchmarks, cost routing, integrations, or ship readiness.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_platform_overview", {}, result), "degraded": True}

    if any(kw in msg for kw in ["benchmark", "benchmarks", "eval", "evals", "quality", "false positive", "catch rate", "promotion"]):
        result = ck_benchmark_summary()
        urls = result.get("urls", {})
        lines = [
            "🧪 **BENCHMARKS + EVALS + POLICY PROMOTION**",
            "CK turns evidence into evals: findings → scenarios → benchmark runs → policy promotion/rollback.",
            f"- Benchmarks: {urls.get('benchmarks')}",
            f"- History: {urls.get('history')}",
            f"- Scenarios: {urls.get('scenarios')}",
            f"- Evals: {urls.get('evals')}",
            f"- Regressions: {urls.get('regressions')}",
            "Use this to prove scanner quality, catch-rate, false-positive behavior, and agent improvement over time.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_benchmark_summary", {}, result), "degraded": True}

    if any(kw in msg for kw in ["observability", "observe", "improvement loop", "audit log", "trends", "regression", "recommendations"]):
        result = ck_observability_summary()
        urls = result.get("urls", {})
        lines = [
            "📈 **OBSERVABILITY + CONTINUOUS IMPROVEMENT**",
            "CK records events, findings, reviews, budget, task graph, provider health, and improvement signals.",
            f"- Overview: {urls.get('overview')}",
            f"- Improvement loop: {urls.get('loop')}",
            f"- Costs: {urls.get('costs')}",
            f"- Trends: {urls.get('trends')}",
            f"- Regressions: {urls.get('regressions')}",
            "Next: use findings/proofs to create regression scenarios, promote policies, and track whether agents improve over time.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_observability_summary", {}, result), "degraded": True}

    if any(kw in msg for kw in ["policy", "policies", "domain pack", "compliance", "gdpr", "hipaa", "tool policy", "rules"]):
        result = ck_policy_summary()
        urls = result.get("urls", {})
        domains = result.get("domains", {}).get("domains") or result.get("domains", {}).get("data") or []
        lines = [
            "⚖️ **POLICY + COMPLIANCE CONTROL PLANE**",
            "CK supports baseline, software, security, cost, GDPR, healthcare/HIPAA, finance, legal, HR, marketing, sales, real estate, government, insurance, ecommerce, logistics, manufacturing, nonprofit, and education policy packs.",
            f"- Policy Studio: {urls.get('policy_studio')}",
            f"- Workspace tool policy: {urls.get('tool_policy')}",
            f"- Domains discovered: {len(domains) if isinstance(domains, list) else 'available'}",
            "Next: choose the domain pack for the project, validate code/config/shell against it, and gate high-risk actions with review.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_policy_summary", {}, result), "degraded": True}

    if any(kw in msg for kw in ["self learning", "self-learning", "learn", "memory", "prior decisions", "remembered", "continuous learning"]):
        query = message
        result = ck_learning_summary(query)
        urls = result.get("urls", {})
        lines = [
            "🧠 **SELF-LEARNING + TYPED MEMORY**",
            "CK stores durable briefs, decisions, findings, proofs, goals, checkpoints, and incidents so future agents inherit governed context.",
            f"- Memory quality: {urls.get('memory_quality')}",
            f"- Session memory: {urls.get('session_memory')}",
            "Next: record architecture/security/product decisions with `remember: ...`, then search them before future work.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_learning_summary", {"query": query[:100]}, result), "degraded": True}



    if any(kw in msg for kw in ["integration", "integrations", "install", "skills", "providers", "models", "route", "deploy"]):
        result = ck_integration_summary()
        urls = result.get("urls", {})
        lines = [
            "🔌 **INTEGRATIONS + PROVIDERS + DEPLOYMENT**",
            "CK attaches to agent hosts, exposes skills/MCP tools, tracks provider health/cost, and supports Cloud Run/self-host deploys.",
            f"- Install: {urls.get('install')}",
            f"- Skills: {urls.get('skills')}",
            f"- Deploy: {urls.get('deploy')}",
            f"- Provider/cost observability: {urls.get('providers')}",
            "Next: choose your host (Claude Code, Cursor, Codex, Copilot, OpenCode, Gemini, etc.) and attach CK governance.",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_integration_summary", {}, result), "degraded": True}

    # Implementation plan
    if any(kw in msg for kw in ["build", "implement", "add feature", "create", "plan", "architecture", "design"]):
        ctx = ck_context()
        budget = ck_budget()
        review = ck_submit_review("plan", f"Governed plan request:\n\n{message}\n\nAll code/config/shell must be validated via ck_validate before execution. Diffs require review gates. Proof bundle required before completion.", f"Plan: {message[:60]}")
        rid = (review.get("review") or review).get("id", "pending")
        lines = [
            "📋 **GOVERNED IMPLEMENTATION PLAN**",
            f"Review gate created (id: {rid}). Approve in Mission Control before execution.",
            "",
            "**Governance contract:**",
            "1. Validate all generated code with `ck_validate` before running it.",
            "2. Submit diffs with `ck_submit_review(type='diff')` before merge.",
            "3. Generate proof bundle with `ck_generate_proof` before shipping.",
            "",
            "Paste the first code snippet or diff and I'll validate it now.",
            f"[Mission Control]({CK_BASE_URL}/missions/1)",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_context", {}, ctx) + tr("ck_submit_review", {"review_type": "plan"}, review), "degraded": True}

    # Ship / proof / release
    if any(kw in msg for kw in ["ship", "proof", "audit", "release", "ready to merge", "ready to deploy"]):
        ctx = ck_context()
        budget = ck_budget()
        proof = ck_generate_proof()
        proof_data = proof.get("proof") or proof
        status = proof_data.get("status", "available") if isinstance(proof_data, dict) else "unknown"
        remaining = budget.get("remaining_cents", "?")
        lines = [
            "🚢 **SHIP READINESS CHECK**",
            f"Proof bundle status: **{status}**",
            f"Budget remaining: {remaining}¢",
            "",
            "Do not ship if: critical/high findings unresolved, reviews pending, proof not generated.",
            f"[Proofs]({CK_BASE_URL}/proofs) — [Findings]({CK_BASE_URL}/findings) — [Reviews]({CK_BASE_URL}/ship)",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_context", {}, ctx) + tr("ck_budget", {}, budget) + tr("ck_generate_proof", {}, proof), "degraded": True}

    # Budget
    if any(kw in msg for kw in ["budget", "cost", "spend", "tokens"]):
        result = ck_budget()
        rem = result.get("remaining_cents", "?")
        total = result.get("budget_cents", "?")
        return {"response": f"💰 **Budget**: {rem}¢ of {total}¢ remaining. CK circuit breaker activates at 0 — agents cannot silently exceed budget.", "trace": tr("ck_budget", {}, result), "degraded": True}

    # Memory record
    if any(kw in msg for kw in ["remember", "record decision", "save this", "memory"]):
        content = message
        for t in ["remember:", "record decision:", "save:"]:
            if t in msg:
                content = message[msg.index(t) + len(t):].strip()
                break
        result = ck_memory_record(content, "decision")
        return {"response": f"📝 **Decision recorded** in durable CK memory (survives sessions and host switches):\n> {content}", "trace": tr("ck_memory_record", {"memory": content[:80]}, result), "degraded": True}

    # Context / state / findings
    if any(kw in msg for kw in ["context", "state", "findings", "mission control", "what's active"]):
        ctx = ck_context()
        session = (ctx.get("session") or ctx) if isinstance(ctx, dict) else {}
        lines = [
            f"🧠 **Session state** (id: {session.get('id', '?')})",
            f"[Mission Control]({CK_BASE_URL}/missions/1) — [Findings]({CK_BASE_URL}/findings) — [Proofs]({CK_BASE_URL}/proofs)",
        ]
        return {"response": "\n".join(lines), "trace": tr("ck_context", {}, ctx), "degraded": True}

    # Default: validate as text, show capabilities
    result = ck_validate(message, "text")
    return {
        "response": (
            "**ControlKeel Studio** governs real software workflows. Try:\n"
            "- Paste a **GitHub URL** → risk analysis + review gate\n"
            "- Paste **code/shell/config** → deterministic validation\n"
            "- Ask to **build a feature** → governed implementation plan\n"
            "- Say **ship/proof/ready** → release readiness check\n"
            "- Say **remember: [decision]** → persist to durable memory"
        ),
        "trace": tr("ck_validate", {"content": message[:80], "kind": "text"}, result),
        "degraded": True,
    }


# ── Turn entry point ─────────────────────────────────────────────────────────
def _try_gemini_polish(user_message: str, governed: dict) -> str | None:
    """Use Gemini to explain the already-executed CK result; no tool calls."""
    if not GEMINI_API_KEY:
        return None
    try:
        from google import genai
        from google.genai import types
        client = genai.Client(api_key=GEMINI_API_KEY)
        governed_for_prompt = {k: v for k, v in governed.items() if k != "degraded"}
        prompt = f"""
You are ControlKeel Studio. The live ControlKeel API has ALREADY executed this governance workflow.
Do not invent tool calls. Do not claim deployment happened unless the trace says so.
Explain the result usefully and concretely for a software team.

User request:
{user_message}

Executed CK result:
{governed_for_prompt}

Return a concise answer with governance status and next step.
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


def run_turn(user_message: str, history: list[dict] | None = None) -> dict:
    """
    Run one governed agent turn.
    CK governance executes deterministically first. Gemini may explain broader
    workflows, but validation decisions stay verbatim so BLOCK/WARN/ALLOW labels
    cannot be softened or misreported by model prose.
    """
    governed = _direct_ck(user_message)
    first_tool = (governed.get("trace") or [{}])[0].get("tool")
    if first_tool == "ck_validate":
        return governed
    polished = _try_gemini_polish(user_message, governed)
    if polished:
        governed["response"] = polished
        governed["degraded"] = False
    return governed


# ── Routes ────────────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return render_template_string(UI_HTML, ck_url=CK_BASE_URL, model=GEMINI_MODEL, gemini_ready=bool(GEMINI_API_KEY))


@app.route("/chat", methods=["POST"])
def chat():
    data = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    history = data.get("history") or []
    if not message:
        return jsonify({"error": "message required"}), 400
    try:
        return jsonify(run_turn(message, history))
    except Exception as exc:
        return jsonify({"response": f"Error: {exc}", "trace": [], "error": str(exc)}), 200


def _health_payload():
    sid, tid = _ensure_session()
    ck_alive = _ck_get("/").get("_status", 500) < 500
    return jsonify({"ok": True, "ck_alive": ck_alive, "session_id": sid, "task_id": tid, "gemini": bool(GEMINI_API_KEY)})


@app.route("/health")
@app.route("/healthz")
@app.route("/healthz/", strict_slashes=False)
def healthz():
    return _health_payload()


# ── UI ────────────────────────────────────────────────────────────────────────
UI_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>ControlKeel Studio</title>
<style>
:root{
  --bg:#06070d;--surface:#0f1118;--surface2:#161923;--border:#252b38;
  --fg:#eef1ff;--muted:#7b8499;--accent:#7c3aed;--accent2:#2563eb;
  --green:#22c55e;--yellow:#f59e0b;--red:#ef4444;--cyan:#06b6d4;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden}
body{font-family:Inter,-apple-system,Segoe UI,sans-serif;background:var(--bg);color:var(--fg);display:flex;flex-direction:column}

/* header */
header{display:flex;align-items:center;gap:10px;padding:14px 20px;border-bottom:1px solid var(--border);flex-shrink:0;background:rgba(6,7,13,.9);backdrop-filter:blur(16px)}
header h1{font-size:17px;font-weight:700;background:linear-gradient(120deg,#fff 0%,#a78bfa 60%,#60a5fa 100%);-webkit-background-clip:text;-webkit-text-fill-color:transparent;white-space:nowrap}
.nav{display:flex;gap:6px;flex-wrap:wrap}
.pill{font-size:11px;padding:4px 10px;border-radius:999px;border:1px solid var(--border);color:var(--muted);white-space:nowrap}
.pill a{color:#a78bfa;text-decoration:none}
.pill a:hover{text-decoration:underline}
.pill.live{border-color:rgba(34,197,94,.4);color:var(--green)}
.spacer{flex:1}

/* layout */
.layout{display:flex;flex:1;overflow:hidden}
.sidebar{width:240px;flex-shrink:0;border-right:1px solid var(--border);display:flex;flex-direction:column;background:var(--surface);overflow-y:auto}
.chat-area{flex:1;display:flex;flex-direction:column;overflow:hidden}

/* sidebar */
.sidebar-section{padding:14px 14px 10px;border-bottom:1px solid var(--border)}
.sidebar-label{font-size:10px;font-weight:700;letter-spacing:.1em;color:var(--muted);text-transform:uppercase;margin-bottom:10px}
.action-btn{width:100%;text-align:left;padding:9px 11px;border-radius:9px;border:1px solid var(--border);background:transparent;color:var(--fg);font-size:12px;cursor:pointer;margin-bottom:6px;line-height:1.4}
.action-btn:hover{background:var(--surface2);border-color:var(--accent)}
.action-btn strong{display:block;color:#ddd;margin-bottom:2px}
.action-btn span{color:var(--muted)}
.link-list{display:flex;flex-direction:column;gap:6px;padding:12px 14px}
.mc-link{display:flex;align-items:center;gap:7px;font-size:12px;color:#a78bfa;text-decoration:none;padding:7px 9px;border-radius:8px;border:1px solid var(--border)}
.mc-link:hover{background:rgba(124,58,237,.12);border-color:rgba(124,58,237,.4)}
.mc-link .dot{width:7px;height:7px;border-radius:50%;background:var(--green);flex-shrink:0}

/* messages */
#log{flex:1;overflow-y:auto;padding:18px 20px;display:flex;flex-direction:column;gap:14px;scroll-behavior:smooth}
.msg{padding:13px 15px;border-radius:14px;border:1px solid var(--border);background:var(--surface);line-height:1.55;font-size:14px;max-width:820px}
.msg.user{align-self:flex-end;background:#1a1640;border-color:#3b1f72;max-width:70%}
.msg-content{white-space:pre-wrap;word-break:break-word}
/* markdown-ish rendering */
.msg-content strong{color:#e2e8f0}
.msg-content code{background:#1e2030;border-radius:4px;padding:1px 5px;font-family:ui-monospace,Menlo,monospace;font-size:12px;color:#7dd3fc}
.msg-content pre{background:#0d1117;border:1px solid var(--border);border-radius:8px;padding:12px;overflow-x:auto;margin:8px 0}
.msg-content pre code{background:none;padding:0;color:#c9d1d9}
.msg-content a{color:#a78bfa;text-decoration:none}
.msg-content a:hover{text-decoration:underline}
.msg-content ul{padding-left:18px;margin:6px 0}

/* trace */
.trace{margin-top:10px;padding-top:10px;border-top:1px dashed var(--border);display:flex;flex-direction:column;gap:5px}
.tool-call{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:var(--muted);padding:5px 8px;background:#0a0c12;border-radius:6px;border:1px solid var(--border)}
.badge{display:inline-flex;align-items:center;font-size:10px;font-weight:800;padding:2px 7px;border-radius:5px;margin-right:5px}
.b-allow{background:rgba(34,197,94,.15);color:var(--green)}
.b-warn{background:rgba(245,158,11,.15);color:var(--yellow)}
.b-block{background:rgba(239,68,68,.15);color:var(--red)}

/* input */
.input-area{padding:14px 20px;border-top:1px solid var(--border);background:var(--bg);flex-shrink:0}
.input-row{display:flex;gap:10px;align-items:flex-end}
textarea{flex:1;min-height:52px;max-height:180px;padding:13px 14px;border-radius:12px;border:1px solid var(--border);background:var(--surface);color:var(--fg);font-size:14px;resize:none;font-family:inherit;line-height:1.4}
textarea:focus{outline:none;border-color:rgba(124,58,237,.6)}
textarea::placeholder{color:var(--muted)}
.send-btn{padding:14px 22px;border-radius:12px;border:0;background:linear-gradient(135deg,#7c3aed,#2563eb);color:#fff;font-weight:700;font-size:14px;cursor:pointer;white-space:nowrap;flex-shrink:0}
.send-btn:disabled{opacity:.45;cursor:wait}
.hint{font-size:11px;color:var(--muted);margin-top:7px}

/* welcome */
.welcome{max-width:560px;margin:auto;text-align:center;padding:30px 20px}
.welcome h2{font-size:24px;margin-bottom:12px;background:linear-gradient(120deg,#fff,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.welcome p{color:var(--muted);font-size:14px;line-height:1.6}

/* spinner */
.spinner{display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.2);border-top-color:var(--accent);border-radius:50%;animation:spin .7s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}

@media(max-width:700px){.sidebar{display:none}.msg.user{max-width:90%}}
</style>
</head>
<body>
<header>
  <h1>⎈ ControlKeel Studio</h1>
  <div class="nav">
    <span class="pill live">{{ 'Gemini live' if gemini_ready else 'CK fallback mode' }}</span>
    <span class="pill">{{ model }}</span>
    <span class="pill"><a href="{{ ck_url }}/findings" target="_blank">Findings ↗</a></span>
    <span class="pill"><a href="{{ ck_url }}/proofs" target="_blank">Proofs ↗</a></span>
    <span class="pill"><a href="{{ ck_url }}/missions/1" target="_blank">Mission Control ↗</a></span>
  </div>
</header>

<div class="layout">
  <aside class="sidebar">
    <div class="sidebar-section">
      <div class="sidebar-label">Govern a project</div>
      <button class="action-btn" onclick="ask('Govern this open source repo: https://github.com/langchain-ai/langchain')"><strong>LangChain (AI agents)</strong><span>Fetch repo + risk analysis</span></button>
      <button class="action-btn" onclick="ask('Govern this repo: https://github.com/vercel/next.js')"><strong>Next.js app</strong><span>Review Dockerfile, deps, config</span></button>
      <button class="action-btn" onclick="ask('I want to govern my own project. Here is the tech stack: Node.js, Express, Postgres, deployed on AWS. What should I set up?')"><strong>My own project</strong><span>Custom governance setup</span></button>
    </div>
    <div class="sidebar-section">
      <div class="sidebar-label">Validate code</div>
      <button class="action-btn" onclick="ask('Validate this code:\neval(user_input)')"><strong>Block RCE</strong><span>eval/exec → BLOCK</span></button>
      <button class="action-btn" onclick="ask('Validate this code:\napi_key = \"sk-proj-abc123def456\"')"><strong>Block secret leak</strong><span>Entropy detection</span></button>
      <button class="action-btn" onclick="ask('Validate this shell:\nrm -rf /')"><strong>Block destructive shell</strong><span>Shell tripwires</span></button>
      <button class="action-btn" onclick="ask('Validate this code:\ndef health_check():\n    return {\"status\": \"ok\"}')"><strong>Allow safe code</strong><span>0 findings → ALLOW</span></button>
    </div>
    <div class="sidebar-section">
      <div class="sidebar-label">Build & ship</div>
      <button class="action-btn" onclick="ask('Build a user auth system with JWT tokens, email verification, and rate limiting. Create a governed implementation plan.')"><strong>Build auth feature</strong><span>Governed plan + review gate</span></button>
      <button class="action-btn" onclick="ask('I am ready to ship. Check budget, findings, and generate a proof bundle.')"><strong>Ship readiness check</strong><span>Budget + proof + findings</span></button>
      <button class="action-btn" onclick="ask('Remember: we decided to use JWT for auth, RSA-256 signing, 24h expiry, refresh token rotation.')"><strong>Record decision</strong><span>Durable typed memory</span></button>
    </div>
    <div class="sidebar-section">
      <div class="sidebar-label">Platform value</div>
      <button class="action-btn" onclick="ask('Show me the full ControlKeel platform overview: governance, observability, policies, self-learning, benchmarks, integrations.')"><strong>Full platform</strong><span>Everything CK controls</span></button>
      <button class="action-btn" onclick="ask('Show observability, audit log, improvement loop, trends, and regressions.')"><strong>Observability</strong><span>Audit + feedback loop</span></button>
      <button class="action-btn" onclick="ask('Show policies, domain packs, compliance controls, and tool policy.')"><strong>Policies</strong><span>Domain/compliance packs</span></button>
      <button class="action-btn" onclick="ask('Show self-learning memory and prior decisions.')"><strong>Self-learning</strong><span>Typed memory + recall</span></button>
      <button class="action-btn" onclick="ask('Show benchmarks, evals, regressions, and policy promotion.')"><strong>Benchmarks</strong><span>Evals + quality proof</span></button>
    </div>
    <div class="sidebar-section">
      <div class="sidebar-label">Mission Control</div>
      <div class="link-list" style="padding:0;gap:5px">
        <a class="mc-link" href="{{ ck_url }}/missions/1" target="_blank"><span class="dot"></span>Mission Control</a>
        <a class="mc-link" href="{{ ck_url }}/findings" target="_blank"><span class="dot"></span>Findings</a>
        <a class="mc-link" href="{{ ck_url }}/proofs" target="_blank"><span class="dot"></span>Proof Bundles</a>
        <a class="mc-link" href="{{ ck_url }}/benchmarks" target="_blank"><span class="dot"></span>Benchmarks</a>
        <a class="mc-link" href="{{ ck_url }}/ship" target="_blank"><span class="dot"></span>Ship Readiness</a>
      </div>
    </div>
  </aside>

  <div class="chat-area">
    <div id="log">
      <div class="welcome">
        <h2>Govern any agent workflow.</h2>
        <p>Paste a GitHub URL, code snippet, shell command, config, or PR diff.
        ControlKeel validates it, creates findings, opens review gates, tracks budget,
        observes the workflow, learns durable memory, applies policy packs,
        benchmarks quality, and generates proof bundles — all in real time.</p>
      </div>
    </div>
    <div class="input-area">
      <div class="input-row">
        <textarea id="m" placeholder="Paste code, a GitHub URL, shell command, PR diff, or ask for a governed implementation plan…" rows="2"></textarea>
        <button class="send-btn" id="b" onclick="send()">Govern →</button>
      </div>
      <div class="hint">Enter to send · Shift+Enter for new line · Every action runs through live ControlKeel governance</div>
    </div>
  </div>
</div>

<script>
const log = document.getElementById('log');
const inp = document.getElementById('m');
const btn = document.getElementById('b');
const history = [];

// Simple markdown renderer (bold, code, links, lists, headers)
function renderMd(text) {
  text = text
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/```([\s\S]*?)```/g, (_, c) => `<pre><code>${c.trim()}</code></pre>`)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\)]+)\)/g, '<a href="$2" target="_blank">$1</a>')
    .replace(/^#{1,3} (.+)$/gm, '<strong>$1</strong>')
    .replace(/^- (.+)$/gm, '<li>$1</li>')
    .replace(/(<li>.*<\/li>(\n|$))+/g, s => `<ul>${s}</ul>`);
  return text;
}

function decisionBadge(result) {
  if (!result) return '';
  const s = JSON.stringify(result);
  if (/"decision":\s*"block"/.test(s)) return '<span class="badge b-block">BLOCK</span>';
  if (/"decision":\s*"warn"/.test(s)) return '<span class="badge b-warn">WARN</span>';
  if (/"decision":\s*"allow"/.test(s)) return '<span class="badge b-allow">ALLOW</span>';
  return '';
}

function addMsg(cls, html) {
  // Remove welcome screen on first message
  const w = log.querySelector('.welcome');
  if (w) w.remove();
  const d = document.createElement('div');
  d.className = 'msg ' + cls;
  d.innerHTML = html;
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
  return d;
}

function ask(text) { inp.value = text; inp.focus(); }

async function send() {
  const text = inp.value.trim();
  if (!text || btn.disabled) return;

  addMsg('user', `<div class="msg-content">${text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}</div>`);
  history.push({ role: 'user', content: text });
  inp.value = '';
  btn.disabled = true;

  const waiting = addMsg('', '<div class="msg-content"><span class="spinner"></span> running governed workflow…</div>');

  try {
    const res = await fetch('/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, history: history.slice(-10) })
    });
    const d = await res.json();
    waiting.remove();

    let traceHtml = '';
    if (d.trace && d.trace.length) {
      traceHtml = '<div class="trace">';
      for (const t of d.trace) {
        traceHtml += `<div class="tool-call">${decisionBadge(t.result)}<strong>${t.tool}</strong>(${JSON.stringify(t.args || {}).slice(0,120)})</div>`;
      }
      traceHtml += '</div>';
    }
    const responseText = d.response || '(no response)';
    addMsg('', `<div class="msg-content">${renderMd(responseText)}</div>${traceHtml}`);
    history.push({ role: 'assistant', content: responseText });
  } catch (e) {
    waiting.remove();
    addMsg('', `<div class="msg-content" style="color:var(--red)">Network error: ${e}</div>`);
  }

  btn.disabled = false;
  inp.focus();
}

inp.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
});
</script>
</body>
</html>"""

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
