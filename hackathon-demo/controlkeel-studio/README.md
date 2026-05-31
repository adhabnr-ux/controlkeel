# ControlKeel Studio — AI Studio app

This is the canonical hackathon hosted prototype. It is a real Node/Vite/Express AI Studio app that executes live ControlKeel workflows first, then optionally asks Gemini to polish already-executed results.

Live URL: <https://controlkeel-studio-834811228927.us-west1.run.app>
Mission Control backend: <https://controlkeel-834811228927.us-central1.run.app>
AI Studio app: <https://ai.studio/apps/155ae41c-4f18-4a7c-b337-6d03d1a6142f>

## Runtime config

Set these on AI Studio / Cloud Run:

```
CK_BASE_URL=https://controlkeel-834811228927.us-central1.run.app
APP_URL=https://controlkeel-studio-834811228927.us-west1.run.app
GEMINI_API_KEY=<Secret Manager or AI Studio secret>
```

Do not commit real API keys.

## Local run

```bash
npm install
CK_BASE_URL=https://controlkeel-834811228927.us-central1.run.app GEMINI_API_KEY=$GEMINI_API_KEY npm run dev
```

## Verify

```bash
npm run lint
npm run build
curl https://controlkeel-studio-834811228927.us-west1.run.app/health
```

Smoke prompts:

- `Validate this code: eval(user_input)` → must return `GOVERNANCE: BLOCK` with `ck_validate` trace.
- `Show me the full ControlKeel platform overview` → must return `ck_platform_overview` trace.
