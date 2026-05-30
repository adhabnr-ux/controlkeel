# Google AI Studio Setup — ControlKeel Studio

Use this to create the AI Studio share link required for the "Code Repository"
submission field.

**The live prototype (what judges actually use):**
https://ck-gemini-834811228927.us-central1.run.app

---

## Setup steps

1. Open https://aistudio.google.com
2. Create a new prompt → select **Gemini 2.5 Flash**
3. **System instructions** → paste the full contents of `MASTER_PROMPT.md`
4. **Tools** → add function declarations → paste the contents of `functions.json`
5. In the prompt body paste this starter:

   ```
   You are ControlKeel Studio. Govern a real software project or validate code.

   Try one of:
   - Govern this repo: https://github.com/langchain-ai/langchain
   - Validate this code: eval(user_input)
   - Build a user auth system. Create a governed implementation plan.
   - Check budget and generate a proof bundle before shipping.
   ```

6. Click **Share → Publish** → set to **"Anyone with the link can view"**
7. Copy the share URL — this is your code repo / AI Studio link for submission

---

## Important: what AI Studio shows vs what the app executes

| | Raw AI Studio | Cloud Run app |
|---|---|---|
| Function calls | Gemini returns `functionCall` — you paste responses manually | Python `google-genai` SDK auto-executes each call |
| Hits real CK API | ❌ Not automatically | ✅ Yes, every tool call |
| Purpose | Shows agent design + tool surface for judges to review | The actual live prototype |

When demoing to judges, drive the demo from the **Cloud Run app**. Use the AI
Studio link as the "code repo" submission item.

---

## Good demo prompts for AI Studio

These show the agent design clearly (even without live execution):

```
Govern this open source repo: https://github.com/langchain-ai/langchain
```
→ Gemini issues `ck_validate_github_repo` — shows the governance tool surface

```
Validate this code: eval(user_input)
```
→ Gemini issues `ck_validate(content="eval(user_input)", kind="code")` → explain you'd see `decision: block, rule: security.code_execution`

```
I want to add a payment integration. Create a governed implementation plan.
```
→ Gemini issues `ck_context`, then `ck_submit_review(type="plan", ...)` → shows the review gate workflow

```
We're ready to ship. Check budget and generate a proof bundle.
```
→ Gemini issues `ck_context`, `ck_budget`, `ck_generate_proof` → shows the ship-readiness workflow

Then direct judges to https://ck-gemini-834811228927.us-central1.run.app to
see the same tool calls **actually execute** against the live ControlKeel backend.
