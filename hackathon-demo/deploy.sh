#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# One-command Cloud Run deploy for the whole demo:
#   1. ControlKeel governance backend  (deploy-ck.sh)
#   2. AI Studio governed-agent prototype (deploy-app.sh)
#
#   export GOOGLE_CLOUD_PROJECT="my-project"
#   export GEMINI_API_KEY="..."           # https://aistudio.google.com/apikey
#   ./hackathon-demo/deploy.sh
#
# NOTE: the CK image builds Elixir/OTP from source (~20–25 min the first time).
# Run this the NIGHT BEFORE. The AI Studio app build is ~2 min.
# ═══════════════════════════════════════════════════════════════════════════

HERE="$(cd "$(dirname "$0")" && pwd)"
: "${GEMINI_API_KEY:?❌ Set GEMINI_API_KEY before running (https://aistudio.google.com/apikey)}"

echo "════════ Step 1/2: ControlKeel backend ════════"
"$HERE/deploy-ck.sh"

CK_SERVICE="${CK_SERVICE:-controlkeel}"
REGION="${REGION:-us-central1}"
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
CK_URL="$(gcloud run services describe "$CK_SERVICE" --region "$REGION" --project "$PROJECT_ID" --format 'value(status.url)')"

echo ""
echo "════════ Step 2/2: AI Studio prototype ════════"
CK_BASE_URL="$CK_URL" "$HERE/deploy-app.sh"

echo ""
echo "🎉 Done. Submit the AI Studio app URL as your 'Hosted Prototype (Cloud Run)' link."
