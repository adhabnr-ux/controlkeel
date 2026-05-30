#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Deploy ControlKeel (governance backend) to Google Cloud Run.
#
#   GOOGLE_CLOUD_PROJECT=my-proj ./hackathon-demo/deploy-ck.sh
#
# The CK image is an Elixir/OTP release. The Dockerfile builds OTP 27 from
# source, so the FIRST build takes ~20–25 min — run this EARLY (the night
# before), not minutes before the demo. Subsequent deploys reuse the image.
# ═══════════════════════════════════════════════════════════════════════════

CK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
SERVICE="${CK_SERVICE:-controlkeel}"
IMAGE="gcr.io/${PROJECT_ID}/controlkeel"

if [ -z "$PROJECT_ID" ]; then
  echo "❌ Set GOOGLE_CLOUD_PROJECT or run: gcloud config set project YOUR_PROJECT"
  exit 1
fi

echo "⎈ Deploying ControlKeel to Cloud Run"
echo "   project=$PROJECT_ID  region=$REGION  service=$SERVICE"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  --project "$PROJECT_ID" --quiet

echo "🔨 Building image (Elixir/OTP from source — be patient, ~20–25 min)…"
gcloud builds submit "$CK_ROOT" \
  --tag "$IMAGE" \
  --timeout=3600 \
  --machine-type=e2-highcpu-8 \
  --project "$PROJECT_ID"

# SECRET_KEY_BASE is generated here at runtime — never hardcoded in the repo.
SECRET_KEY_BASE="$(python3 -c 'import secrets; print(secrets.token_hex(64))')"

echo "🚀 Deploying service…"
# CK_MCP_MODE=0 + PHX_SERVER=true force the web server (the image defaults to
# stdio MCP mode). min-instances=1 keeps it warm so judges never hit a cold
# start, and keeps the SQLite demo state alive for the event.
gcloud run deploy "$SERVICE" \
  --image "$IMAGE" \
  --region "$REGION" \
  --project "$PROJECT_ID" \
  --allow-unauthenticated \
  --platform managed \
  --memory 1Gi --cpu 1 \
  --min-instances 1 --max-instances 3 \
  --timeout 300 \
  --set-env-vars "PHX_SERVER=true,CK_MCP_MODE=0,CONTROLKEEL_RUNTIME_MODE=local,CONTROLKEEL_BUS=local,SECRET_KEY_BASE=${SECRET_KEY_BASE},DATABASE_PATH=/app/data/controlkeel.db" \
  --quiet

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"

echo ""
echo "✅ ControlKeel live: $URL"
echo "🔎 Smoke test (should print decision=block):"
curl -s -X POST "$URL/api/v1/validate" \
  -H 'Content-Type: application/json' \
  -d '{"content":"eval(user_input)","kind":"code"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('   decision =',d.get('decision'),' rules =',[f.get('rule_id') for f in d.get('findings',[])])" 2>/dev/null \
  || echo "   (could not parse — check $URL/api/v1/sessions manually)"

echo ""
echo "➡️  Next: export CK_BASE_URL=$URL and run ./hackathon-demo/deploy-app.sh"
