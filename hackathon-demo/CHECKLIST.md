# Demo-Day Checklist — GDG Stanford / DeepMind Hackathon

Event: **May 31, 2026, 10 AM–6 PM PT** · in-person submit by **2:30 PM**.
Required deliverables: one-pager, hosted prototype (AI Studio & **Cloud Run**),
2-min team video, 1-min prototype video (Playcast, shared publicly), code repo.

## Night before (do NOT leave for the morning)
- [ ] Prereq assignment submitted (GCP billing enabled, Cloud Run reachable).
- [ ] `gcloud auth login` && `gcloud config set project <PROJECT>`.
- [ ] `export GOOGLE_CLOUD_PROJECT=<PROJECT>` and `export GEMINI_API_KEY=<key>`.
- [ ] **Run `./hackathon-demo/deploy.sh`** — the CK image builds OTP from source
      (~20–25 min). Do this early; don't discover the build time at 1 PM.
- [ ] Confirm CK: `curl <CK_URL>/api/v1/validate -d '{"content":"eval(user_input)","kind":"code"}' -H 'Content-Type: application/json'` → `decision: block`.
- [ ] Confirm app: open the `ck-gemini` URL, type `Validate this code: eval(user_input)` → red **BLOCK** badge.
- [ ] Open `<CK_URL>/missions/1`, `/findings` — they load (local mode, no login).
- [ ] **Record the 1-min Playcast** of the app blocking `eval` + showing a proof.
      This is also your live-demo fallback.
- [ ] Record the 2-min team video.

## Morning of
- [ ] Re-warm both Cloud Run services (one request each) — min-instances=1 should
      already keep them warm, but click to be sure.
- [ ] Fill real URLs into `submission/ONE_PAGER.md` (prototype, Mission Control, repo, video).
- [ ] Share the YouTube demo video **publicly** (engagement counts toward score).
- [ ] Practice `DEMO_SCRIPT.md` once, end to end, on the live app.

## The 6 lines to type (all verified to work)
1. `Validate this code: eval(user_input)` → BLOCK (RCE)
2. `Validate this code: def health(): return 1` → ALLOW
3. `Validate this shell: rm -rf /` → BLOCK
4. `Validate: api_key = 'sk-proj-abc123def456ghi789'` → BLOCK (secret)
5. `Validate this code: model.eval()` → ALLOW (no false positive)
6. `Remember: we decided to use JWT for auth` → memory recorded

## Failure playbook
- **App is slow on first click** → cold start; click once to warm, then present.
- **A tool call errors** → app degrades gracefully and still shows the CK decision;
  keep going, or re-type the line.
- **CK backend down / build failed** → point the app at a fallback CK
  (`CK_BASE_URL` env on the `ck-gemini` service) or redeploy CK; meanwhile keep
  demoing with the recorded Playcast.
- **Whole thing wedged** → play the recorded 1-min video. Never debug on stage.

## Claims discipline (judges include DeepMind/OpenAI researchers)
- Show **live** catches as proof (`eval`, secret, `rm -rf /`, SQLi) — reproducible.
- For "1/12 vs 12/12", say it's **documented** (`docs/benchmark-evidence.md`) and
  that the raw baseline wasn't a perfectly clean isolation. Don't overclaim.
- Don't click into `/benchmarks` live (empty on a fresh deploy) unless you've
  imported a run.
