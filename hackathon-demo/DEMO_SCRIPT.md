# ControlKeel Studio — Recording Scripts

> App URL: <https://controlkeel-studio-834811228927.us-west1.run.app>
> Mission Control: <https://controlkeel-834811228927.us-central1.run.app/missions/1>
> Open both tabs before recording. Click each once to warm them.

---

## Playcast — 1-Minute Demo (record this first, post to YouTube public)

Screen-record the app. Narrate over it. No typing needed — click the sidebar chips.

### [0:00–0:10] Hook

Open the app. Stay on the welcome screen for a beat.

> "42% of enterprises have AI agents in production. Almost none have governance.
> A rules file in a system prompt is a suggestion. ControlKeel makes it a hard block."

### [0:10–0:28] Govern a real repo

Click sidebar chip **LangChain (AI agents)** under "Govern a project".

Wait for the response. Show the decision badge and Mission Control link in the response.

> "This fetches the actual repo files from GitHub and runs real-time governance.
> A review gate just opened in Mission Control."

Flip to the Mission Control tab for 2 seconds. Flip back.

### [0:28–0:45] Block dangerous code

Click sidebar chip **Block RCE** under "Validate code".

Wait for the red BLOCK badge in the trace.

> "50 milliseconds. Zero LLM tokens. Deterministic, not probabilistic. Same
> result every single time."

Click sidebar chip **Allow safe code**.

Wait for green ALLOW badge.

> "And it doesn't over-block. A clean health-check function — zero findings, green
> ALLOW. False positives are how governance gets turned off. Precision matters as
> much as recall."

### [0:45–0:55] Platform depth

Click sidebar chip **Full platform** under "Platform value".

Scroll the response briefly to show the depth.

> "Proof bundles, budget circuit breakers, human review gates, typed memory,
> policy packs for GDPR, HIPAA, finance. 40-plus host integrations."

### [0:55–1:00] Close

Cut to you on camera or narrate over the app.

> "I've been working on this problem for a while. ControlKeel is already built.
> Go to controlkeel.com — you can attach it to any agent you're running today,
> your subscription and telemetry live on your machine."

---

## Team Intro — 2-Minute Solo Video (record second, post to YouTube public)

On camera. Relaxed, direct. No slide deck needed.

### [0:00–0:25] Who you are and the problem

> "I'm Bibek. I've been building ControlKeel because I kept running into the same
> problem: 42% of enterprises have AI agents in production. Almost none have
> governance. A markdown rules file in a system prompt is not enforcement. When the
> agent writes code that touches your database, or spends your budget, or touches
> patient data, you need a real control, not a suggestion."

### [0:25–1:00] What it does (show the app or screen-share clip)

> "So ControlKeel sits between the agent and execution. Every tool call gets
> validated before anything happens.
>
> I built this demo using Gemini 2.5 Flash and Google AI Studio, hosted on Cloud
> Run. When I ask it to govern a real GitHub repo, it fetches the actual files,
> runs a 6-layer deterministic scanner in about 50 milliseconds, zero LLM tokens,
> and creates a review gate in Mission Control.
>
> When code with eval() comes in, it's blocked. Hardcoded secrets, blocked.
> Destructive shell commands, blocked. But model.eval() — PyTorch's method — is
> allowed, because precision matters as much as recall."

### [1:00–1:35] Platform, proof, and market

> "Beyond validation: proof bundles for SOC 2 and GDPR, budget circuit breakers
> so agents can't silently run up cost, typed cross-session memory that survives
> host switches, policy packs for healthcare, finance, and legal workflows.
>
> In a documented run on a 12-scenario unsafe-code suite, a raw GPT-5.5 agent
> caught 1 of 12. ControlKeel's deterministic scanner caught 12 of 12 in ~50
> milliseconds, zero tokens. Those catches are reproducible — you just watched
> four of them live.
>
> And while building this prototype, ControlKeel blocked our own deploy command
> for putting the Gemini API key inline in an env var. That's how the deploy
> script actually works now — it governs the people building the agent too.
>
> The AI governance market is $8.4 billion by 2028. Teams shipping agents in
> regulated industries have no good answer to 'how do you prove the agent followed
> the rules.' ControlKeel is the answer: deterministic, auditable, portable."

### [1:35–2:00] Call to action

> "ControlKeel is the trust infrastructure for the agent era: deterministic
> enforcement, human review gates, proof bundles, budget control, 40-plus host
> integrations. If you're funding the paved path for enterprise AI, this is it.
>
> Go to controlkeel.com. You can attach it to any agent you're running today —
> Claude Code, Cursor, your own tool loop — subscription and telemetry live on
> your machine. Thank you."

---

## Numbers you can defend

| Claim | Evidence |
|---|---|
| `eval(user_input)` → BLOCK | Live in the app, reproducible on demand |
| `model.eval()` → ALLOW | Live in the app — proves no false positives |
| ~50 ms, 0 tokens | Visible in the trace panel below each response |
| 1/12 vs 12/12 on unsafe-code suite | `docs/benchmark-evidence.md` (host_comparison_v1, runs #29/#31). Caveat: raw baseline was not a clean no-CK isolation — full methodology in the doc |
| 40+ host integrations | CK platform |
| SOC 2, GDPR, EU AI Act compliance packs | CK policy studio |

---

## If something breaks during recording

| Problem | Fix |
|---|---|
| App slow on first click | Cold start. Click once to warm, wait 10s, then record |
| Chip sends wrong message | You can also type directly in the input box |
| GitHub fetch times out | Try the Next.js chip instead, or paste a snippet directly |
| CK backend down | `./hackathon-demo/deploy-ck.sh` then retry |
| Everything down | Re-record just the 1-min Playcast after fixing — platform tour is optional |
