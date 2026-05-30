# Google AI Studio Setup — ControlKeel Studio

This is the hackathon "AI Studio sharing mechanics" artifact. The actual hosted
prototype is the Cloud Run app:

https://ck-gemini-834811228927.us-central1.run.app

## Create the AI Studio prompt

1. Open https://aistudio.google.com
2. Create a new prompt using Gemini 2.5 Flash.
3. Paste `MASTER_PROMPT.md` as the **System instruction**.
4. Add the function declarations from `functions.json`.
5. In the prompt body, paste this starter message:

```text
You are ControlKeel Studio. Help me govern a real software project.
Start by asking for one of: a GitHub URL, package files, Dockerfile, auth code,
a shell command, config, or PR diff. For any code/config/shell/diff, call
ck_validate before recommending execution. For plans, submit a review gate. For
release readiness, check budget and generate a proof bundle.
```

6. Click **Share / Publish** and set access to **Anyone with the link can view**.
7. Use that AI Studio share URL as the "Code Repository / AI Studio share" link.

## Important note for judges

Raw AI Studio returns function calls; it does not execute CK HTTP calls by itself.
The Cloud Run app is the executor: Python `google-genai` runs the tool calls and
sends them to the live ControlKeel API. The AI Studio prompt shows the same
agent design and tool surface for review/share.

## What to demonstrate in AI Studio

- Ask: `Govern this repo: https://github.com/example/agent-app`
- Ask: `Validate this code: eval(user_input)`
- Ask: `Create a governed plan for adding registration and checkout`
- Ask: `Before shipping, check budget and proof readiness`

Then point judges to the Cloud Run prototype to see the tools execute live.
