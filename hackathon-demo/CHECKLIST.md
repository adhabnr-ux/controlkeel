# Demo-Day Checklist — GDG Stanford / DeepMind Hackathon

**Event:** May 31, 2026 · 10 AM–6 PM PT · submit by **2:30 PM sharp**

**Deliverables:** one-pager · hosted prototype (Cloud Run) · 2-min team video ·
1-min Playcast (public YouTube) · code repo / AI Studio share link

---

## Night before (do NOT leave these for the morning)

- [ ] `gcloud auth login` — confirm account is `sunim.54@gmail.com`
- [ ] `gcloud config set project fluted-torus-424408-s6`
- [ ] `export GEMINI_API_KEY=<your-key>`
- [ ] **`./hackathon-demo/deploy.sh`** — CK builds OTP from source (~20–25 min first time).
      Run this early. Subsequent redeploys reuse the cached image (~2 min).
- [ ] Smoke-test CK:

      ```bash
      curl -s -X POST https://controlkeel-834811228927.us-central1.run.app/api/v1/validate \
        -H 'Content-Type: application/json' \
        -d '{"content":"eval(user_input)","kind":"code"}' \
        | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['decision'],d['findings'][0]['rule_id'])"
      ```

      Expected: `block  security.code_execution`

- [ ] Open <https://controlkeel-studio-834811228927.us-west1.run.app>
      → type `Validate this code: eval(user_input)` → red **BLOCK** badge ✓
- [ ] Open <https://controlkeel-834811228927.us-central1.run.app/missions/1> → loads ✓
- [ ] Open <https://controlkeel-834811228927.us-central1.run.app/findings> → loads ✓
- [ ] **Record 1-min Playcast** (public YouTube):
      GitHub repo governance → BLOCK eval → ALLOW safe code → proof bundle.
      This is also your live-demo fallback if anything breaks.
- [ ] Record 2-min team intro video.
- [ ] Fill video + repo links into `submission/ONE_PAGER.md`.
- [ ] Run through `DEMO_SCRIPT.md` once end-to-end on the live app.

---

## Morning of

- [ ] Re-warm both URLs with one click each.
- [ ] Confirm YouTube Playcast is set to **public** (engagement counts toward score).
- [ ] Have `DEMO_SCRIPT.md` open on second monitor or phone.

---

## The 8 lines to type (all verified to work)

```text
1.  Govern this open source repo: https://github.com/langchain-ai/langchain
2.  Validate this code: eval(user_input)
3.  Validate this code: def health(): return {"status": "ok"}
4.  Validate: api_key = 'sk-proj-abc123def456ghi789'
5.  Validate this shell: rm -rf /
6.  Validate this code: model.eval()
7.  Build a user auth system with JWT. Create a governed implementation plan.
8.  Remember: we decided to use JWT, RSA-256 signing, 24-hour expiry
```

Expected outcomes:

- **Line 1** → GitHub files fetched + risk assessment + review gate in Mission Control
- **Lines 2, 4, 5** → 🚫 BLOCK with rule shown in trace
- **Lines 3, 6** → ✅ ALLOW (line 6 proves no false positive on `model.eval()`)
- **Line 7** → plan submitted, review gate visible in Mission Control
- **Line 8** → `ck_memory_record` → decision persisted in typed memory

---

## Submission links (fill in before 2:30 PM)

| Item | Link |
| --- | --- |
| Hosted prototype | <https://controlkeel-studio-834811228927.us-west1.run.app> |
| Mission Control | <https://controlkeel-834811228927.us-central1.run.app/missions/1> |
| Code repo / AI Studio | _(fill in after sharing in AI Studio)_ |
| 2-min team video | _(fill in)_ |
| 1-min Playcast | _(fill in)_ |

---

## Failure playbook

| Problem | Fix |
| --- | --- |
| App slow on first click | Cold start — click once to warm, then present |
| A tool call errors | App degrades gracefully, CK decision still shows; keep going |
| GitHub fetch times out | Try a smaller repo or paste a snippet directly |
| CK backend down | `./hackathon-demo/deploy-ck.sh`; or swap `CK_BASE_URL` on the controlkeel-studio service |
| Everything broken | Play the recorded Playcast — never debug on stage |

---

## Claims discipline (judges include DeepMind / OpenAI researchers)

- **Lead with live catches** — eval, secret, rm -rf /, SQLi are reproducible on stage.
- For "1/12 vs 12/12": cite `docs/benchmark-evidence.md` (host_comparison_v1 runs
  \#29/\#31) and add: *"the raw baseline wasn't a perfectly clean no-CK isolation —
  full methodology is in the doc."*
- `/benchmarks` on a fresh deploy is empty — do not click into it live.
