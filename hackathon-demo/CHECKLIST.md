# Demo-Day Checklist — GDG Stanford / DeepMind Hackathon

**Event:** May 31, 2026 · Online track · deadline end of day PT

**Solo presenter:** Bibek Aryal

**Deliverables:** one-pager · hosted prototype (Cloud Run) · 2-min solo video ·
1-min Playcast (public YouTube) · code repo / AI Studio share link

The submission form for the online track will be shared by the organizers before end of day. Same format as in-person.

---

## Before you record

- [ ] Open <https://controlkeel-studio-834811228927.us-west1.run.app> — click once to warm it up
- [ ] Open <https://controlkeel-834811228927.us-central1.run.app/missions/1> — confirm it loads
- [ ] Smoke test in the app: click **Block RCE** chip → confirm red BLOCK badge appears

If the smoke test fails:

```bash
curl -s -X POST https://controlkeel-834811228927.us-central1.run.app/api/v1/validate \
  -H 'Content-Type: application/json' \
  -d '{"content":"eval(user_input)","kind":"code"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['decision'],d['findings'][0]['rule_id'])"
```

Expected: `block  security.code_execution`

If CK backend is down: `./hackathon-demo/deploy-ck.sh`

---

## Recording order

### 1. Record the 1-min Playcast first (this is the scored video)

Follow `DEMO_SCRIPT.md` → Playcast section. Key chip clicks in order:

| Chip | Section | Expected result |
| --- | --- | --- |
| **LangChain (AI agents)** | Govern a project | Risk assessment + review gate |
| **Block RCE** | Validate code | 🚫 BLOCK — `security.code_execution` |
| **Allow safe code** | Validate code | ✅ ALLOW — 0 findings |
| **Full platform** | Platform value | Platform depth overview |

End with: *"Go to controlkeel.com — attach it to any agent you're running today."*

Upload to YouTube → set **Public** immediately. Every hour it's live counts toward Phase 2 engagement scoring.

### 2. Record the 2-min solo intro video

Follow `DEMO_SCRIPT.md` → Team Intro section. On camera, straight to the problem.

Upload to YouTube → set **Public**.

### 3. Create the AI Studio share link (5 min)

1. Go to [aistudio.google.com](https://aistudio.google.com) → New prompt → Gemini 2.5 Flash
2. System instructions → paste all of `hackathon-demo/MASTER_PROMPT.md`
3. Tools → paste all of `hackathon-demo/functions.json`
4. Share → "Anyone with the link" → copy URL

### 4. Fill in submission links

Open `submission/ONE_PAGER.md` and add the three links:

| Item | Link |
| --- | --- |
| Hosted prototype | <https://controlkeel-studio-834811228927.us-west1.run.app> |
| Mission Control | <https://controlkeel-834811228927.us-central1.run.app/missions/1> |
| Code / AI Studio | *(paste AI Studio share link)* |
| 2-min video | *(paste YouTube link)* |
| 1-min Playcast | *(paste YouTube link)* |

### 5. Submit

Wait for the organizer to post the online track Google Form link (by end of day). Fill it out with all five deliverables.

---

## Failure playbook

| Problem | Fix |
| --- | --- |
| App slow on first chip click | Cold start — wait 10s and click again |
| Chip fires but no badge appears | Type directly in the input box instead |
| GitHub fetch times out | Click **Next.js app** chip instead, or paste a snippet |
| CK backend down | `./hackathon-demo/deploy-ck.sh` then retry |
| App won't load at all | Redeploy: `export GEMINI_API_KEY=... && ./hackathon-demo/deploy-app.sh` |

---

## Claims discipline (judges include DeepMind / OpenAI researchers)

- Lead with live catches — eval, secret, rm -rf /, SQLi are all reproducible on demand.
- For "1/12 vs 12/12": cite `docs/benchmark-evidence.md` (host_comparison_v1 runs
  #29/#31). Add: *"the raw baseline wasn't a perfectly clean no-CK isolation — full methodology is in the doc."*
- Do not click into `/benchmarks` in the live app — it is empty on a fresh deploy.

Phase 2 judging tracks Playcast YouTube engagement metrics for two weeks post-event. Post early, share the link.
