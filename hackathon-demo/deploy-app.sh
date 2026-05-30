#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Deploy the Gemini governed-agent app (the hackathon "prototype") to Cloud Run.
# This is the link judges open. It uses the google-genai SDK's automatic
# function calling so Gemini's tool calls REALLY hit the live ControlKeel API.
#
#   export CK_BASE_URL="https://controlkeel-xxxxx-uc.a.run.app"   # from deploy-ck.sh
#   export GEMINI_API_KEY="..."                                   # aistudio.google.com/apikey
#   ./hackathon-demo/deploy-app.sh
#
# Python build is fast (~2 min). The Gemini key goes through Secret Manager —
# never inlined as an env var (ControlKeel's own scanner blocks that).
# ═══════════════════════════════════════════════════════════════════════════

APP_DIR="$(cd "$(dirname "$0")/app" && pwd)"
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
SERVICE="${APP_SERVICE:-ck-gemini}"
SECRET_NAME="${SECRET_NAME:-ck-gemini-key}"

[ -z "$PROJECT_ID" ] && { echo "❌ Set GOOGLE_CLOUD_PROJECT"; exit 1; }
: "${CK_BASE_URL:?❌ Set CK_BASE_URL to your deployed ControlKeel URL}"
: "${GEMINI_API_KEY:?❌ Set GEMINI_API_KEY (https://aistudio.google.com/apikey)}"

echo "⎈ Deploying Gemini governed-agent app to Cloud Run"
echo "   project=$PROJECT_ID  region=$REGION  service=$SERVICE  ck=$CK_BASE_URL"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com \
  --project "$PROJECT_ID" --quiet

# Store / update the Gemini key in Secret Manager (not in plaintext env).
if gcloud secrets describe "$SECRET_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
  printf '%s' "$GEMINI_API_KEY" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project "$PROJECT_ID"
else
  printf '%s' "$GEMINI_API_KEY" | gcloud secrets create "$SECRET_NAME" --data-file=- --replication-policy=automatic --project "$PROJECT_ID"
fi

# Grant the Cloud Run runtime service account read access to the secret.
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format 'value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member "serviceAccount:${RUNTIME_SA}" \
  --role roles/secretmanager.secretAccessor \
  --project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true

echo "🚀 Deploying service (Python build ~2 min)…"
gcloud run deploy "$SERVICE" \
  --source "$APP_DIR" \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --platform managed \
  --memory 512Mi --cpu 1 \
  --min-instances 1 --max-instances 3 \
  --timeout 120 \
  --set-env-vars "CK_BASE_URL=${CK_BASE_URL},GEMINI_MODEL=${GEMINI_MODEL:-gemini-2.5-flash}" \
  --set-secrets "GEMINI_API_KEY=${SECRET_NAME}:latest" \
  --quiet

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"

echo ""
echo "✅ Gemini app live: $URL"
echo "🔎 Health:"
curl -s "$URL/healthz" || echo "   (warming up — retry in ~10s)"
echo ""
echo "🎤 This URL is your hackathon 'Hosted Prototype' link. Open it and try:"
echo "      Validate this code: eval(user_input)"
