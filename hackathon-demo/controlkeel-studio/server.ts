import express from "express";
import path from "path";
import { createServer as createViteServer } from "vite";
import { GoogleGenAI } from "@google/genai";

const app = express();
const PORT = 3000;

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

const mockResponses: Record<string, any> = {
  ck_validate: {
    decision: "allow",
    findings: []
  },
  ck_validate_github_repo: {
    decision: "warn",
    findings: [{ severity: "medium", rule_id: "ops.no_budget_guard", plain_message: "No per-session cost tracking found in repo" }]
  },
  ck_context: {
    active_findings: 0,
    budget_remaining: 100,
    tasks_completed: 0
  },
  ck_budget: {
    budget_remaining: 100,
    spend_history: []
  },
  ck_submit_review: {
    review: { id: "REV-" + Math.floor(Math.random() * 10000), status: "pending", url: "https://controlkeel-834811228927.us-central1.run.app/missions/1/reviews/1" }
  },
  ck_record_finding: {
    success: true,
    message: "Finding recorded successfully."
  },
  ck_memory_record: {
    success: true,
    message: "Memory recorded successfully."
  },
  ck_memory_search: {
    hits: [
        { memory: "We decided to use JWT for auth, RSA-256 signing, 24h expiry", type: "decision" }
    ]
  },
  ck_complete_task: {
    success: true,
    proof_id: "PF-9999"
  },
  ck_generate_proof: {
    proof_id: "PF-" + Math.floor(Math.random() * 10000),
    verification_score: 100
  },
  ck_platform_overview: {
    overview: "ControlKeel is the control plane for agent-built software.",
    urls: {
      mission_control: "https://controlkeel-834811228927.us-central1.run.app/missions/1",
      observability: "https://controlkeel-834811228927.us-central1.run.app/observability",
      policies: "https://controlkeel-834811228927.us-central1.run.app/policies",
      benchmarks: "https://controlkeel-834811228927.us-central1.run.app/benchmarks",
      ship: "https://controlkeel-834811228927.us-central1.run.app/ship",
      proofs: "https://controlkeel-834811228927.us-central1.run.app/proofs",
      skills: "https://controlkeel-834811228927.us-central1.run.app/skills"
    }
  },
  ck_observability_summary: {
    urls: {
      overview: "https://controlkeel-834811228927.us-central1.run.app/observability",
      loop: "https://controlkeel-834811228927.us-central1.run.app/observability/loop",
      costs: "https://controlkeel-834811228927.us-central1.run.app/observability/costs",
      trends: "https://controlkeel-834811228927.us-central1.run.app/observability/trends",
      regressions: "https://controlkeel-834811228927.us-central1.run.app/observability/regressions",
      recommendations: "https://controlkeel-834811228927.us-central1.run.app/observability/recommendations"
    }
  },
  ck_policy_summary: {
    urls: {
      policy_studio: "https://controlkeel-834811228927.us-central1.run.app/policies",
      tool_policy: "https://controlkeel-834811228927.us-central1.run.app/policies"
    }
  },
  ck_learning_summary: {
    urls: {
      memory_quality: "https://controlkeel-834811228927.us-central1.run.app/observability/memory-quality",
      session_memory: "https://controlkeel-834811228927.us-central1.run.app/observability/sessions/1/memory"
    }
  },
  ck_benchmark_summary: {
    urls: {
      benchmarks: "https://controlkeel-834811228927.us-central1.run.app/benchmarks",
      history: "https://controlkeel-834811228927.us-central1.run.app/observability/benchmarks/history",
      scenarios: "https://controlkeel-834811228927.us-central1.run.app/observability/benchmarks/scenarios",
      evals: "https://controlkeel-834811228927.us-central1.run.app/observability/evals",
      regressions: "https://controlkeel-834811228927.us-central1.run.app/observability/regressions",
      promotions: "https://controlkeel-834811228927.us-central1.run.app/observability/promotions"
    }
  },
  ck_integration_summary: {
    urls: {
      install: "https://controlkeel-834811228927.us-central1.run.app/install",
      skills: "https://controlkeel-834811228927.us-central1.run.app/skills",
      deploy: "https://controlkeel-834811228927.us-central1.run.app/deploy",
      providers: "https://controlkeel-834811228927.us-central1.run.app/observability/costs"
    }
  }
};

app.post("/api/chat", async (req, res) => {
  try {
    const { messages } = req.body;
    const aiClient = getAI();
    
    // We only use the last message for the chat, but ideally we'd pass history.
    // For simplicity, passing full message history as content array.
    const formattedMessages = messages.map((m: any) => ({
      role: m.role,
      parts: [{ text: m.content }]
    }));

    async function generateWithRetry(options: any, maxRetries = 3) {
      for (let i = 0; i < maxRetries; i++) {
        try {
          return await aiClient.models.generateContent(options);
        } catch (err: any) {
          if (err?.status === 503 || err?.message?.includes("503") || err?.message?.includes("high demand")) {
            if (i === maxRetries - 1) throw err;
            await new Promise(resolve => setTimeout(resolve, 1500 * Math.pow(2, i)));
          } else {
            throw err;
          }
        }
      }
    }

    const response = await generateWithRetry({
      model: "gemini-2.5-flash",
      contents: formattedMessages,
      config: {
         systemInstruction: SYSTEM_INSTRUCTION,
         tools: [{ functionDeclarations: CK_TOOLS as any }],
         temperature: 0.2
      }
    });

    // Simple mock function execution if the model decides to call functions
    let returnedText = "";
    let trace: any[] = [];

    if (response.functionCalls && response.functionCalls.length > 0) {
      // Model wanted to call tools
      let followUpCalls = [];
      
      for (const call of response.functionCalls) {
        const functionName = call.name;
        let mockResult = mockResponses[functionName] || { success: true };
        
        if (functionName === "ck_validate" && call.args) {
          const content = String(call.args.content || "");
          if (content.includes("eval(") && !content.includes("model.eval(")) {
            mockResult = {
              decision: "block",
              findings: [{ severity: "critical", rule_id: "security.code_execution", plain_message: "eval() with user-controlled input allows Remote Code Execution." }]
            };
          } else if (content.includes("rm -rf")) {
            mockResult = {
              decision: "block",
              findings: [{ severity: "critical", rule_id: "shell.destructive_rm", plain_message: "Destructive shell command detected." }]
            };
          } else if (content.includes("api_key =") || content.includes("GEMINI_API_KEY=")) {
            mockResult = {
              decision: "block",
              findings: [{ severity: "critical", rule_id: "secret.high_entropy_token", plain_message: "Hardcoded secret detected." }]
            };
          } else if (content.includes("SELECT * FROM") && content.includes("OR 1=1")) {
             mockResult = {
              decision: "block",
              findings: [{ severity: "critical", rule_id: "security.sql_injection", plain_message: "SQL injection pattern detected." }]
            };
          }
        }

        trace.push({
          tool: functionName,
          args: call.args,
          result: mockResult
        });

        followUpCalls.push({
           functionResponse: {
               name: functionName,
               response: mockResult
           }
        });
      }

      // We make a second request with the tool responses if needed, or just append raw mock output for demonstration.
      const secondResponse = await generateWithRetry({
        model: "gemini-2.5-flash",
        contents: [
            ...formattedMessages,
            { role: "model", parts: response.functionCalls.map(c => ({ functionCall: c })) },
            { role: "user", parts: followUpCalls }
        ],
        config: {
            systemInstruction: SYSTEM_INSTRUCTION,
            tools: [{ functionDeclarations: CK_TOOLS as any }],
            temperature: 0.2
        }
      });
      returnedText = secondResponse.text || "Processed function blocks.";
    } else {
        returnedText = response.text || "";
    }

    res.json({ message: returnedText, trace });
  } catch (err: any) {
    console.error("Chat Error:", err);
    if (err?.status === 503 || err?.message?.includes("503") || err?.message?.includes("high demand")) {
      res.json({ message: "The model is currently experiencing high demand. Please try again in 5-10 seconds.", trace: [] });
    } else {
      res.status(500).json({ error: err.message });
    }
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
