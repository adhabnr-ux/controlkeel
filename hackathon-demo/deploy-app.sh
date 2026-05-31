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
REGION="${REGION:-us-west1}"
SERVICE="${APP_SERVICE:-controlkeel-studio}"
SECRET_NAME="${SECRET_NAME:-controlkeel-studio-gemini-key}"
APP_URL="${APP_URL:-https://controlkeel-studio-834811228927.us-west1.run.app}"

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

echo "🚀 Building container image…"
IMAGE="gcr.io/${PROJECT_ID}/${SERVICE}:$(date +%Y%m%d%H%M%S)"
gcloud builds submit "$APP_DIR" --tag "$IMAGE" --project "$PROJECT_ID" --quiet

# AI Studio-created Cloud Run services carry source/base-image annotations that can
# reject normal image deploys. Apply a clean service spec so the live URL keeps
# working while runtime config comes from real env/Secret Manager values.
TMP_YAML="$(mktemp)"
cat > "$TMP_YAML" <<YAML
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  annotations:
    generativelanguage.googleapis.com/type: fullstack-applet
    run.googleapis.com/ingress: all
    run.googleapis.com/invoker-iam-disabled: "true"
    run.googleapis.com/urls: '["${APP_URL}"]'
  labels:
    cloud.googleapis.com/location: ${REGION}
    managed-by: google-ai-studio
  name: ${SERVICE}
  namespace: "${PROJECT_NUMBER}"
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        run.googleapis.com/cpu-throttling: "true"
        run.googleapis.com/sessionAffinity: "false"
    spec:
      containerConcurrency: 80
      containers:
      - env:
        - name: CK_BASE_URL
          value: ${CK_BASE_URL}
        - name: APP_URL
          value: ${APP_URL}
        - name: GEMINI_MODEL
          value: ${GEMINI_MODEL:-gemini-2.5-flash}
        - name: GEMINI_API_KEY
          valueFrom:
            secretKeyRef:
              name: ${SECRET_NAME}
              key: latest
        image: ${IMAGE}
        name: app-container
        ports:
        - containerPort: 8080
          name: http1
        resources:
          limits:
            cpu: "1"
            memory: 512Mi
      serviceAccountName: ${RUNTIME_SA}
      timeoutSeconds: 120
  traffic:
  - latestRevision: true
    percent: 100
YAML

echo "🚀 Deploying service from clean Cloud Run spec…"
gcloud run services replace "$TMP_YAML" --region "$REGION" --project "$PROJECT_ID" --quiet
rm -f "$TMP_YAML"

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"

echo ""
echo "✅ ControlKeel Studio live: $URL"
echo "🔎 Health:"
curl -s "$URL/health" || echo "   (warming up — retry in ~10s)"
echo ""
echo "🎤 This URL is your hackathon 'Hosted Prototype' link. Open it and try:"
echo "      Validate this code: eval(user_input)"
