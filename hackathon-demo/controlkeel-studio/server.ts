import express from "express";
import path from "path";
import { createServer as createViteServer } from "vite";
import { GoogleGenAI } from "@google/genai";

const app = express();
const PORT = Number(process.env.PORT || 3000);
const CK_BASE_URL = (process.env.CK_BASE_URL || "https://controlkeel-834811228927.us-central1.run.app").replace(/\/$/, "");

app.use(express.json());

const SYSTEM_INSTRUCTION = `You are **ControlKeel Studio**: a governed Gemini product assistant for real software teams. You help users govern their own product, open-source repo, or AI agent workflow using a live, hosted ControlKeel governance platform.

**Hosted prototype (live executor):** https://ck-gemini-834811228927.us-central1.run.app
**Mission Control:** https://controlkeel-834811228927.us-central1.run.app/missions/1
**Findings:** https://controlkeel-834811228927.us-central1.run.app/findings

---

## What you actually do

You are not a toy demo. You help users with real software governance:

1. **Govern a GitHub repo** — analyse a real repository by calling \`ck_validate_github_repo(github_url)\`. This fetches the README, Dockerfile, package.json, etc. and runs a real CK risk assessment.
2. **Validate code/config/shell** — call \`ck_validate(content, kind)\` before recommending any execution. The scanner catches eval/exec (RCE), hardcoded secrets, SQL injection, destructive shell, PII exposure, and 12+ more patterns in ~50ms with zero LLM tokens.
3. **Create governed plans** — when a user wants to build something, call \`ck_submit_review(type="plan", ...)\` to create a review gate in Mission Control before claiming execution-ready.
4. **Record decisions** — call \`ck_memory_record(memory, record_type)\` for architecture decisions, security posture choices, and product direction. These survive sessions, restarts, and host switches.
5. **Ship safely** — call \`ck_context()\` + \`ck_budget()\` + \`ck_generate_proof()\` before release.
6. **Build a full project** — when asked to build an app, produce a complete, runnable project: requirements, architecture, file tree, source files, tests, Dockerfile, Cloud Run deployment commands, validation checklist, and submit a CK review gate before claiming execution-ready.
7. **Prepare Cloud Run deployment** — generate \`Dockerfile\`, \`.dockerignore\`, env/Secret Manager plan, \`gcloud run deploy\` command, health endpoint, smoke tests, and rollback notes. Do **not** claim it is deployed unless an execution environment actually ran the commands and returned URLs.
8. **Show observability** — call \`ck_observability_summary()\` to explain audit log, task graph, improvement loop, costs, trends, regressions, and recommendations.
9. **Operate policy** — call \`ck_policy_summary()\` to explain baseline/software/security/cost/domain packs, compliance controls, and workspace tool policy.
10. **Use self-learning** — call \`ck_learning_summary(query)\` and \`ck_memory_record\`/\`ck_memory_search\` to show durable typed memory and prior decisions.
11. **Benchmark quality** — call \`ck_benchmark_summary()\` to show benchmark/eval/regression/promotion surfaces and scanner evidence.
12. **Integrate/deploy** — call \`ck_integration_summary()\` to show agent-host integrations, skills, provider routing/cost, install, and deploy surfaces.

---

## Full platform operating modes

Use these modes when the user asks what else CK does beyond validation:

### Observability mode
Call \`ck_observability_summary()\`. Explain that CK records recent events, audit logs, task graph, findings, reviews, budgets, provider status, cost trends, regression evidence, and improvement recommendations. Point to \`/observability\`, \`/observability/loop\`, \`/observability/costs\`, \`/observability/trends\`, \`/observability/regressions\`, and \`/observability/recommendations\`.

### Self-learning mode
Call \`ck_learning_summary(query)\` plus \`ck_memory_record\` / \`ck_memory_search\`. Explain typed memory: briefs, decisions, findings, proofs, goals, checkpoints, incidents. Emphasize that future agents retrieve durable, citable context instead of relying on hidden provider memory.

### Policy mode
Call \`ck_policy_summary()\`. Explain baseline + software + security + cost + domain packs: GDPR, healthcare/HIPAA, finance, legal, HR, marketing, sales, real estate, government, insurance, ecommerce, logistics, manufacturing, nonprofit, education. Explain workspace tool policy and review gates for high-impact actions.

### Benchmark/eval mode
Call \`ck_benchmark_summary()\`. Explain the loop: findings → scenarios → benchmark runs → false-positive/catch-rate metrics → policy promotion/rollback. Keep claims honest: benchmark evidence is documented; live demo proves deterministic catches.

### Integration/deploy mode
Call \`ck_integration_summary()\`. Explain host attachment, skills, MCP/API surfaces, provider status, cost routing, Cloud Run/self-host deployment, and protocol endpoints.

### Platform overview mode
Call \`ck_platform_overview()\`. Use this when the user asks “show everything” or judges want the full value story. Summarize governance, observability, learning, policies, benchmarks, integrations, proof, budget, and ship readiness in one response with links.

---

## Response style

Be **concrete and useful**. Give next commands, file-level plans, exact fixes — not just descriptions.
`;

const CK_TOOLS = [
  {
    "name": "ck_validate",
    "description": "Validate code, config, shell commands, or text against ControlKeel's 6-layer deterministic scanner (pattern rules, entropy detection, destructive-shell tripwires, trust-boundary checks, security-workflow phases, optional Semgrep). Runs in ~50ms with zero LLM tokens. Returns allow/warn/block with findings and auto-fix suggestions. Call BEFORE writing files or running commands.",
    "parameters": {
      "type": "object",
      "properties": {
        "content": {"type": "string", "description": "Content to validate: source code, config, shell command, or text."},
        "kind": {"type": "string", "enum": ["code","config","shell","text"], "description": "Content kind."},
        "source_type": {"type": "string", "enum": ["developer","generated","tool_output","human_review","web","issue","pull_request"], "description": "Content origin. 'generated' gets stricter scrutiny."}
      },
      "required": ["content","kind"]
    }
  },
  {
    "name": "ck_validate_github_repo",
    "description": "Fetch key files (README.md, Dockerfile, package.json, pyproject.toml, requirements.txt, go.mod, etc.) from a public GitHub repository and run ControlKeel governance analysis. Returns a risk assessment with findings, recommended governance setup, and file context. Use when the user provides a GitHub URL.",
    "parameters": {
      "type": "object",
      "properties": {
        "github_url": {"type": "string", "description": "Full GitHub URL, e.g. https://github.com/langchain-ai/langchain"}
      },
      "required": ["github_url"]
    }
  },
  {
    "name": "ck_context",
    "description": "Get full governed session state: active findings, budget, tasks, memory hits, proof summary, improvement loop, autonomy profile, workspace context. Call at start of every task.",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  },
  {
    "name": "ck_budget",
    "description": "Check remaining budget, spend history, session limits. CK tracks per-invocation cost with circuit breakers that stop agents from silently burning budget.",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  },
  {
    "name": "ck_submit_review",
    "description": "Submit a plan, diff, or completion for human review. Creates a review gate visible in Mission Control. Plans must be approved before execution proceeds.",
    "parameters": {
      "type": "object",
      "properties": {
        "review_type": {"type": "string", "enum": ["plan","diff","completion"], "description": "What is being reviewed."},
        "submission_body": {"type": "string", "description": "Full submission content: plan text, diff, or completion description."},
        "title": {"type": "string", "description": "Short review title shown in Mission Control."}
      },
      "required": ["review_type","submission_body"]
    }
  },
  {
    "name": "ck_record_finding",
    "description": "Record a governance finding with severity, category, and ruling. Use when you discover issues the scanner did not raise automatically.",
    "parameters": {
      "type": "object",
      "properties": {
        "category": {"type": "string", "enum": ["security","compliance","performance","operations","decision-hygiene"]},
        "severity": {"type": "string", "enum": ["critical","high","medium","low"]},
        "rule_id": {"type": "string", "description": "Policy rule ID, e.g. 'security.missing_rate_limit'."},
        "plain_message": {"type": "string", "description": "Human-readable description of the issue."},
        "decision": {"type": "string", "enum": ["allow","warn","block","escalate_to_human"]}
      },
      "required": ["category","severity","rule_id","plain_message"]
    }
  },
  {
    "name": "ck_memory_record",
    "description": "Save durable memory that survives sessions and host switches. Typed records with semantic-search retrieval for decisions, briefs, checkpoints, and findings.",
    "parameters": {
      "type": "object",
      "properties": {
        "memory": {"type": "string", "description": "Content to save."},
        "record_type": {"type": "string", "enum": ["brief","decision","finding","proof","goal","checkpoint","incident"], "description": "Record type for retrieval filtering."}
      },
      "required": ["memory"]
    }
  },
  {
    "name": "ck_memory_search",
    "description": "Search governed memory for prior decisions, findings, and proofs using embedding-based semantic search.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {"type": "string", "description": "Search query, e.g. 'auth decisions' or 'security findings'."}
      },
      "required": ["query"]
    }
  },
  {
    "name": "ck_generate_proof",
    "description": "Generate an immutable proof bundle: findings, reviews, validation evidence, and a verification score. The ship-ready audit artifact compliance teams need for SOC 2 / GDPR sign-off.",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  },
  {
    "name": "ck_complete_task",
    "description": "Mark the current task done. BLOCKED if unresolved critical or high findings exist. Generates a proof bundle on success.",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  },
  {
    "name": "ck_platform_overview",
    "description": "Return a compact ControlKeel platform snapshot: mission state, budget, findings, proofs, benchmarks, policies, providers, skills, and key Mission Control URLs.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  },
  {
    "name": "ck_observability_summary",
    "description": "Return observability and continuous-improvement signals: improvement loop, audit log, task graph, provider health, costs/trends/regressions URLs.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  },
  {
    "name": "ck_policy_summary",
    "description": "Return active policy surfaces: policy packs, domains, workspace policy sets, workspace tool policy, and policy studio URLs.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  },
  {
    "name": "ck_learning_summary",
    "description": "Return typed memory and self-learning surfaces: semantic memory hits, session context, and memory quality URLs.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Memory search query, e.g. architecture decisions or security findings."
        }
      },
      "required": []
    }
  },
  {
    "name": "ck_benchmark_summary",
    "description": "Return benchmark/eval/regression surfaces and URLs for scanner quality, false-positive tracking, promotions, and policy regression testing.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  },
  {
    "name": "ck_integration_summary",
    "description": "Return host/skill/provider/deploy integration surfaces: agents, skills, providers, provider status, install/deploy URLs.",
    "parameters": {
      "type": "object",
      "properties": {},
      "required": []
    }
  }
];

let ai: GoogleGenAI | null = null;
function getAI() {
  if (!ai) {
    if (!process.env.GEMINI_API_KEY) {
      throw new Error("GEMINI_API_KEY is not set.");
    }
    ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
  }
  return ai;
}

type ChatMessage = { role: "user" | "model" | "assistant"; content: string };

type ToolTrace = { tool: string; args: Record<string, any>; result: any };

const state: { sessionId?: number; taskId?: number } = {};

async function ckGet(path: string, params?: Record<string, any>) {
  const url = new URL(`${CK_BASE_URL}${path}`);
  for (const [key, value] of Object.entries(params || {})) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }
  const response = await fetch(url, { headers: { "Accept": "application/json" } });
  return readJson(response);
}

async function ckPost(path: string, body?: Record<string, any>) {
  const response = await fetch(`${CK_BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify(body || {}),
  });
  return readJson(response);
}

async function readJson(response: Response) {
  const text = await response.text();
  let data: any;
  try { data = text ? JSON.parse(text) : {}; } catch { data = { body: text.slice(0, 500) }; }
  if (!response.ok) {
    return { ...data, _status: response.status, error: data.error || `HTTP ${response.status}` };
  }
  return { ...data, _status: response.status };
}

async function ensureSession() {
  if (state.sessionId) return state;
  const boot = await ckPost("/api/v1/bootstrap", { project_name: "controlkeel-studio-ai-studio", agent: "gemini" });
  const session = boot.session || boot;
  state.sessionId = session?.id;
  if (state.sessionId) {
    const detail = await ckGet(`/api/v1/sessions/${state.sessionId}`);
    const tasks = (detail.session || detail).tasks || [];
    const active = tasks.find((t: any) => ["in_progress", "queued"].includes(t.status)) || tasks[0];
    state.taskId = active?.id;
  }
  return state;
}

function githubUrlFrom(message: string) {
  const match = message.match(/https?:\/\/github\.com\/[^\s)]+/i);
  return match?.[0]?.replace(/[.,]$/, "");
}

async function fetchGithubContext(githubUrl: string) {
  const match = githubUrl.match(/github\.com\/([^/\s]+)\/([^/\s]+)/i);
  if (!match) return { error: "Could not parse GitHub URL.", github_url: githubUrl };
  const owner = match[1];
  const repo = match[2].replace(/\.git$/, "").replace(/[.,]$/, "");
  const metaResp = await fetch(`https://api.github.com/repos/${owner}/${repo}`, {
    headers: { "Accept": "application/vnd.github+json", "User-Agent": "controlkeel-studio" },
  });
  if (!metaResp.ok) return { error: `Could not fetch GitHub metadata: HTTP ${metaResp.status}`, github_url: githubUrl };
  const meta: any = await metaResp.json();
  const branch = meta.default_branch || "main";
  const candidates = ["README.md", "package.json", "Dockerfile", "docker-compose.yml", "requirements.txt", "pyproject.toml", "go.mod", "Cargo.toml", "mix.exs", ".env.example", ".github/workflows/ci.yml", ".github/workflows/deploy.yml"];
  const fetched: { path: string; bytes: number; decision?: string; findings?: any[] }[] = [];
  const allFindings: any[] = [];
  for (const file of candidates) {
    const raw = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${file}`;
    try {
      const r = await fetch(raw);
      if (!r.ok) continue;
      const content = (await r.text()).slice(0, 20000);
      if (!content.trim()) continue;
      const kind = /\.(json|ya?ml|toml|exs)$/.test(file) || file.includes("Dockerfile") ? "config" : "code";
      const result = await ckPost("/api/v1/validate", { content, kind, source_type: "repository" });
      fetched.push({ path: file, bytes: content.length, decision: result.decision, findings: result.findings || [] });
      for (const finding of (result.findings || []).slice(0, 4)) allFindings.push({ path: file, ...finding });
      if (fetched.length >= 8) break;
    } catch (_) {}
  }
  const blocked = fetched.filter(f => f.decision === "block").length;
  const warned = fetched.filter(f => f.decision === "warn").length;
  const decision = blocked ? "block" : warned || allFindings.length ? "warn" : "allow";
  return { github_url: githubUrl, repo: `${owner}/${repo}`, default_branch: branch, decision, files_fetched: fetched, findings: allFindings.slice(0, 12), summary: { blocked, warned, allowed: fetched.filter(f => f.decision === "allow").length, findings: allFindings.length } };
}

function trace(tool: string, args: Record<string, any>, result: any): ToolTrace[] {
  return [{ tool, args, result }];
}

async function runCkWorkflow(message: string) {
  const msg = message.toLowerCase();
  const { sessionId, taskId } = await ensureSession();

  if (githubUrlFrom(message)) {
    const url = githubUrlFrom(message)!;
    const repo = await fetchGithubContext(url);
    const review = await ckPost("/api/v1/reviews", { session_id: sessionId, task_id: taskId, review_type: "plan", title: `Repo governance: ${repo.repo || url}`, submission_body: `Govern repository ${url}. Decision: ${repo.decision}. Findings: ${(repo.findings || []).length}.` });
    const findings = repo.findings || [];
    const lines = [`🧭 **REPO GOVERNANCE ANALYSIS: ${repo.repo || url}**`, `Decision: **${String(repo.decision || "unknown").toUpperCase()}**`, `Files scanned: ${(repo.files_fetched || []).length}`, `Findings: ${findings.length}`];
    for (const finding of findings.slice(0, 5)) lines.push(`- **${String(finding.severity || "?").toUpperCase()}** ${finding.path || "repo"}: \`${finding.rule_id || "unknown"}\` — ${finding.plain_message || ""}`);
    lines.push("", `Review gate: ${(review.review || review).id || "created"}`, `Mission Control: ${CK_BASE_URL}/missions/1`, "Next: paste a PR diff, Dockerfile, auth code, or deployment command and I will validate it live.");
    return { message: lines.join("\n"), trace: [...trace("ck_validate_github_repo", { github_url: url }, repo), ...trace("ck_submit_review", { review_type: "plan" }, review)] };
  }

  if (/(validate|check this|scan|is this safe|review this|diff)/i.test(message) || /eval\(|exec\(|rm -rf|SELECT \*/i.test(message)) {
    let content = message;
    for (const trigger of ["validate this code:", "validate this shell:", "validate this config:", "validate:", "check this:", "scan:", "review this diff:"]) {
      const idx = message.toLowerCase().indexOf(trigger);
      if (idx >= 0) content = message.slice(idx + trigger.length).trim();
    }
    const kind = /rm |gcloud |kubectl |npm run|curl |\$ /.test(content) ? "shell" : "code";
    const result = await ckPost("/api/v1/validate", { content, kind, source_type: "generated" });
    const decision = String(result.decision || "unknown").toUpperCase();
    const findings = result.findings || [];
    const icon = result.decision === "block" ? "🚫" : result.decision === "warn" ? "⚠️" : "✅";
    const lines = [`${icon} **GOVERNANCE: ${decision}**`];
    if (findings.length) {
      for (const f of findings) lines.push(`- **${String(f.severity || "?").toUpperCase()}** \`${f.rule_id || "unknown"}\`: ${f.plain_message || ""}`);
      lines.push("", "Safe next step: fix findings, then paste the corrected code/diff for validation.");
    } else {
      lines.push("No issues found. Snippet passes CK policy.");
    }
    return { message: lines.join("\n"), trace: trace("ck_validate", { content: content.slice(0, 120), kind }, result) };
  }

  if (/(platform overview|all features|everything|full platform|what can controlkeel do)/i.test(message)) {
    const result = await platformOverview(sessionId);
    return { message: `🧭 **CONTROLKEEL PLATFORM OVERVIEW**\n\nControlKeel covers governance, observability, self-learning memory, policy packs, benchmarks/evals, integrations, budget, proof bundles, and ship readiness.\n\n- Mission Control: ${CK_BASE_URL}/missions/1\n- Observability: ${CK_BASE_URL}/observability\n- Policies: ${CK_BASE_URL}/policies\n- Benchmarks: ${CK_BASE_URL}/benchmarks\n- Ship Readiness: ${CK_BASE_URL}/ship\n- Skills: ${CK_BASE_URL}/skills`, trace: trace("ck_platform_overview", {}, result) };
  }

  if (/(benchmark|benchmarks|eval|evals|quality|false positive|catch rate|promotion)/i.test(message)) {
    const result = await ckGet("/api/v1/benchmarks");
    return { message: `🧪 **BENCHMARKS + EVALS**\n\nControlKeel turns findings into scenarios, benchmark runs, regression checks, and policy promotion/rollback evidence.\n\n- Benchmarks: ${CK_BASE_URL}/benchmarks\n- History: ${CK_BASE_URL}/observability/benchmarks/history\n- Evals: ${CK_BASE_URL}/observability/evals\n- Regressions: ${CK_BASE_URL}/observability/regressions\n- Promotions: ${CK_BASE_URL}/observability/promotions`, trace: trace("ck_benchmark_summary", {}, result) };
  }

  if (/(observability|observe|improvement loop|audit log|trends|regression|recommendations)/i.test(message)) {
    const result = { improvement: await ckGet("/api/v1/improvement", { session_id: sessionId }), audit_log: await ckGet(`/api/v1/sessions/${sessionId}/audit-log`, { limit: 20 }), graph: await ckGet(`/api/v1/sessions/${sessionId}/graph`) };
    return { message: `📈 **OBSERVABILITY + IMPROVEMENT LOOP**\n\nCK records audit logs, task graph, findings, reviews, budget, provider status, costs, trends, regressions, and recommendations.\n\n- Overview: ${CK_BASE_URL}/observability\n- Loop: ${CK_BASE_URL}/observability/loop\n- Costs: ${CK_BASE_URL}/observability/costs\n- Trends: ${CK_BASE_URL}/observability/trends\n- Regressions: ${CK_BASE_URL}/observability/regressions`, trace: trace("ck_observability_summary", {}, result) };
  }

  if (/(policy|policies|domain pack|compliance|gdpr|hipaa|tool policy|rules)/i.test(message)) {
    const result = { domains: await ckGet("/api/v1/domains"), policies: await ckGet("/api/v1/policies") };
    return { message: `⚖️ **POLICY + COMPLIANCE CONTROL PLANE**\n\nCK supports baseline/software/security/cost plus domain packs: GDPR, healthcare/HIPAA, finance, legal, HR, marketing, sales, real estate, government, insurance, ecommerce, logistics, manufacturing, nonprofit, education.\n\n- Policy Studio: ${CK_BASE_URL}/policies\n- Tool Policy: ${CK_BASE_URL}/workspaces/1/tool-policy`, trace: trace("ck_policy_summary", {}, result) };
  }

  if (/(self learning|self-learning|learn|memory|prior decisions|remembered|continuous learning)/i.test(message)) {
    const result = await ckGet("/api/v1/memory/search", { session_id: sessionId, query: message });
    return { message: `🧠 **SELF-LEARNING + TYPED MEMORY**\n\nCK stores durable briefs, decisions, findings, proofs, goals, checkpoints, and incidents so future agents retrieve governed context instead of relying on hidden provider memory.\n\n- Memory quality: ${CK_BASE_URL}/observability/memory-quality\n- Session memory: ${CK_BASE_URL}/observability/sessions/1/memory\n\nSay: \`remember: <decision>\` to persist a new decision.`, trace: trace("ck_learning_summary", { query: message }, result) };
  }

  if (/(integration|integrations|install|skills|providers|models|route|deploy)/i.test(message)) {
    const result = { agents: await ckGet("/api/v1/agents"), skills: await ckGet("/api/v1/skills"), providers: await ckGet("/api/v1/providers/status") };
    return { message: `🔌 **INTEGRATIONS + PROVIDERS + DEPLOYMENT**\n\nCK attaches to agent hosts, exposes MCP/API/skill surfaces, tracks provider health and cost, and supports Cloud Run/self-host deployment.\n\n- Install: ${CK_BASE_URL}/install\n- Skills: ${CK_BASE_URL}/skills\n- Deploy: ${CK_BASE_URL}/deploy\n- Provider costs: ${CK_BASE_URL}/observability/costs`, trace: trace("ck_integration_summary", {}, result) };
  }

  if (/(ship|proof|audit|release|ready to merge|ready to deploy)/i.test(message)) {
    const budget = await ckGet("/api/v1/budget", { session_id: sessionId });
    const proof = taskId ? await ckGet(`/api/v1/proof/${taskId}`, { session_id: sessionId }) : { error: "no task" };
    return { message: `🚢 **SHIP READINESS CHECK**\n\nBudget remaining: ${budget.remaining_cents ?? "?"}¢\nProof status: ${(proof.proof || proof).status || "available"}\n\nDo not ship if high/critical findings or pending reviews remain.\n\n- Proofs: ${CK_BASE_URL}/proofs\n- Findings: ${CK_BASE_URL}/findings\n- Ship: ${CK_BASE_URL}/ship`, trace: [...trace("ck_budget", {}, budget), ...trace("ck_generate_proof", {}, proof)] };
  }

  if (/(budget|cost|spend|tokens)/i.test(message)) {
    const result = await ckGet("/api/v1/budget", { session_id: sessionId });
    return { message: `💰 **Budget**: ${result.remaining_cents ?? "?"}¢ of ${result.budget_cents ?? "?"}¢ remaining. CK circuit breaker prevents silent budget burn.`, trace: trace("ck_budget", {}, result) };
  }

  if (/(remember|record decision|save this|memory)/i.test(message)) {
    const memory = message.replace(/^(remember:|record decision:|save:)/i, "").trim();
    const result = await ckPost("/api/v1/memory", { session_id: sessionId, memory, record_type: "decision" });
    return { message: `📝 **Decision recorded** in durable CK memory:\n> ${memory}`, trace: trace("ck_memory_record", { memory: memory.slice(0, 80) }, result) };
  }

  if (/(build|implement|add feature|create|plan|architecture|design)/i.test(message)) {
    const ctx = await ckGet(`/api/v1/sessions/${sessionId}`);
    const review = await ckPost("/api/v1/reviews", { session_id: sessionId, task_id: taskId, review_type: "plan", title: `Plan: ${message.slice(0, 60)}`, submission_body: `Governed build request:\n\n${message}\n\nRequired gates: validate code/config/shell before execution, submit diffs for review, check budget, generate proof before shipping.` });
    return { message: `📋 **GOVERNED IMPLEMENTATION PLAN**\n\nReview gate created: ${(review.review || review).id || "pending"}.\n\nI can build a complete project packet: requirements, architecture, file tree, full source files, tests, Dockerfile, Cloud Run deploy commands, Secret Manager plan, smoke tests, and rollback notes.\n\nBefore execution: validate generated code/config/shell and approve the review gate in Mission Control.\n\nMission Control: ${CK_BASE_URL}/missions/1`, trace: [...trace("ck_context", {}, ctx), ...trace("ck_submit_review", { review_type: "plan" }, review)] };
  }



  const result = await ckPost("/api/v1/validate", { content: message, kind: "text", source_type: "generated" });
  return { message: `**ControlKeel Studio** governs real software workflows. Try a GitHub URL, code/shell/config, build plan, ship readiness, observability, policies, self-learning, benchmarks, or integrations.`, trace: trace("ck_validate", { content: message.slice(0, 80), kind: "text" }, result) };
}

async function platformOverview(sessionId?: number) {
  return { session: sessionId ? await ckGet(`/api/v1/sessions/${sessionId}`) : {}, budget: sessionId ? await ckGet("/api/v1/budget", { session_id: sessionId }) : {}, findings: await ckGet("/api/v1/findings", { session_id: sessionId }), proofs: await ckGet("/api/v1/proofs", { session_id: sessionId }), benchmarks: await ckGet("/api/v1/benchmarks"), policies: await ckGet("/api/v1/policies"), providers: await ckGet("/api/v1/providers/status"), skills: await ckGet("/api/v1/skills") };
}

async function maybePolishWithGemini(userMessage: string, governed: { message: string; trace: ToolTrace[] }) {
  if (!process.env.GEMINI_API_KEY) return governed.message;
  try {
    const aiClient = getAI();
    const response = await aiClient.models.generateContent({
      model: "gemini-2.5-flash",
      contents: [{ role: "user", parts: [{ text: `Explain this already-executed ControlKeel result concisely. Do not invent tool calls or claim deployment happened.\n\nUser: ${userMessage}\n\nResult: ${JSON.stringify(governed).slice(0, 12000)}` }] }],
      config: { systemInstruction: SYSTEM_INSTRUCTION, temperature: 0.2 }
    });
    return response.text || governed.message;
  } catch (err) {
    console.warn("Gemini polish failed; returning CK result", err);
    return governed.message;
  }
}

app.post("/api/chat", async (req, res) => {
  try {
    const { messages } = req.body;
    const latest = Array.isArray(messages) ? messages[messages.length - 1]?.content || "" : "";
    const governed = await runCkWorkflow(latest);
    const message = await maybePolishWithGemini(latest, governed);
    res.json({ message, trace: governed.trace });
  } catch (err: any) {
    console.error("Chat Error:", err);
    res.status(200).json({ message: `🚫 **GOVERNANCE: ERROR**\n\nUnable to connect to Mission Control or run the workflow.\n\nDetails: ${err?.message || String(err)}\n\nCheck CK_BASE_URL (${CK_BASE_URL}) and try again.`, trace: [] });
  }
});

async function startServer() {
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
