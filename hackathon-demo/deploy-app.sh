#!/usr/bin/env bash
set -euo pipefail

# Deploy the canonical AI Studio / Node ControlKeel Studio app to Cloud Run.
# The legacy Python prototype is intentionally not deployed by this script.
#
# Required:
#   export GOOGLE_CLOUD_PROJECT=fluted-torus-424408-s6
#   export GEMINI_API_KEY=...  # only used to create/update Secret Manager; never committed
#   ./hackathon-demo/deploy-app.sh

APP_DIR="$(cd "$(dirname "$0")/controlkeel-studio" && pwd)"
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-west1}"
SERVICE="${APP_SERVICE:-controlkeel-studio}"
SECRET_NAME="${SECRET_NAME:-controlkeel-studio-gemini-key}"
CK_BASE_URL="${CK_BASE_URL:-https://controlkeel-834811228927.us-central1.run.app}"
APP_URL="${APP_URL:-https://controlkeel-studio-834811228927.us-west1.run.app}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"

[ -z "$PROJECT_ID" ] && { echo "❌ Set GOOGLE_CLOUD_PROJECT"; exit 1; }
: "${GEMINI_API_KEY:?❌ Set GEMINI_API_KEY (https://aistudio.google.com/apikey)}"

echo "⎈ Deploying AI Studio ControlKeel Studio to Cloud Run"
echo "   project=$PROJECT_ID region=$REGION service=$SERVICE ck=$CK_BASE_URL"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com \
  --project "$PROJECT_ID" --quiet

if gcloud secrets describe "$SECRET_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
  printf '%s' "$GEMINI_API_KEY" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project "$PROJECT_ID"
else
  printf '%s' "$GEMINI_API_KEY" | gcloud secrets create "$SECRET_NAME" --data-file=- --replication-policy=automatic --project "$PROJECT_ID"
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format 'value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member "serviceAccount:${RUNTIME_SA}" \
  --role roles/secretmanager.secretAccessor \
  --project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true

IMAGE="gcr.io/${PROJECT_ID}/${SERVICE}:$(date +%Y%m%d%H%M%S)"
echo "🚀 Building Node image…"
gcloud builds submit "$APP_DIR" --tag "$IMAGE" --project "$PROJECT_ID" --quiet

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
          value: ${GEMINI_MODEL}
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

echo "🚀 Deploying clean Cloud Run service…"
gcloud run services replace "$TMP_YAML" --region "$REGION" --project "$PROJECT_ID" --quiet
rm -f "$TMP_YAML"

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"
echo ""
echo "✅ ControlKeel Studio live: $APP_URL"
echo "   Cloud Run status URL: $URL"
echo "🔎 Health:"
curl -s "$APP_URL/health" || echo "   (warming up — retry in ~10s)"
echo ""
echo "Try: Validate this code: eval(user_input)"
