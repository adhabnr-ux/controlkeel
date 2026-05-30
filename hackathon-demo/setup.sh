#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════
# ControlKeel × Gemini — One-Command Hackathon Setup
# Deploys CK to fly.io, wires AI Studio master prompt
# ═══════════════════════════════════════════════════════════════════════

CK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "⎈ ControlKeel — Hackathon Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Deploy CK to fly.io (using existing self-host template) ──

echo "📦 Step 1: Deploy ControlKeel to fly.io"
echo ""

if ! command -v fly &>/dev/null; then
    echo "❌ fly CLI not found. Install: curl -L https://fly.io/install.sh | sh"
    exit 1
fi

# Check if already deployed
APP_NAME="ck-hackathon"
if fly status --app "$APP_NAME" &>/dev/null 2>&1; then
    echo "✅ App '$APP_NAME' already exists. Skipping deploy."
    CK_URL=$(fly info --app "$APP_NAME" --json 2>/dev/null | python3 -c "import sys,json; print('https://'+json.load(sys.stdin)['Hostname'])" 2>/dev/null || echo "")
else
    echo "🔧 Creating fly app: $APP_NAME"

    # Use the self-host template
    cp "$CK_ROOT/deploy/fly.self-host.toml" "$DEMO_DIR/fly.toml"

    # Patch for hackathon
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/controlkeel-acme/$APP_NAME/" "$DEMO_DIR/fly.toml"
        sed -i '' 's|govern.acme.com|'"$APP_NAME"'.fly.dev|' "$DEMO_DIR/fly.toml"
        sed -i '' 's|shared-cpu-1x|shared-cpu-1x|' "$DEMO_DIR/fly.toml"
        sed -i '' 's|512mb|256mb|' "$DEMO_DIR/fly.toml"
        sed -i '' 's|CONTROLKEEL_RUNTIME_MODE = "cloud"|CONTROLKEEL_RUNTIME_MODE = "local"|' "$DEMO_DIR/fly.toml"
        sed -i '' 's|min_machines_running = 1|min_machines_running = 0|' "$DEMO_DIR/fly.toml"
        sed -i '' 's|auto_stop_machines = false|auto_stop_machines = true|' "$DEMO_DIR/fly.toml"
    else
        sed -i "s/controlkeel-acme/$APP_NAME/" "$DEMO_DIR/fly.toml"
        sed -i 's|govern.acme.com|'"$APP_NAME"'.fly.dev|' "$DEMO_DIR/fly.toml"
        sed -i 's|CONTROLKEEL_RUNTIME_MODE = "cloud"|CONTROLKEEL_RUNTIME_MODE = "local"|' "$DEMO_DIR/fly.toml"
        sed -i 's|min_machines_running = 1|min_machines_running = 0|' "$DEMO_DIR/fly.toml"
        sed -i 's|auto_stop_machines = false|auto_stop_machines = true|' "$DEMO_DIR/fly.toml"
    fi

    # Launch
    fly launch --no-deploy --copy-config --name "$APP_NAME" --org personal --region iad 2>/dev/null || true

    # Create a SQLite volume (cheaper than Postgres for hackathon)
    fly vol create ck_data --size 1 --app "$APP_NAME" --region iad 2>/dev/null || true

    # Generate secrets
    SECRET_KEY_BASE=$(python3 -c "import secrets; print(secrets.token_hex(64))")
    fly secrets set \
        SECRET_KEY_BASE="$SECRET_KEY_BASE" \
        --app "$APP_NAME"

    # Deploy from CK root
    echo "🚀 Deploying (this takes ~5 minutes for first build)..."
    fly deploy --app "$APP_NAME" --config "$DEMO_DIR/fly.toml" --dockerfile "$CK_ROOT/Dockerfile" --local-only 2>/dev/null || \
    fly deploy --app "$APP_NAME" --config "$DEMO_DIR/fly.toml" 2>/dev/null || \
    fly deploy --app "$APP_NAME"

    CK_URL="https://$APP_NAME.fly.dev"
fi

echo ""
echo "✅ ControlKeel deployed!"
echo "🌐 URL: ${CK_URL:-https://$APP_NAME.fly.dev}"
echo ""

# ── Step 2: Bootstrap CK workspace ──

echo "📦 Step 2: Bootstrap CK workspace"

CK_URL="${CK_URL:-https://$APP_NAME.fly.dev}"

# Wait for CK to be ready
echo "⏳ Waiting for CK to start..."
for i in $(seq 1 30); do
    if curl -sf "$CK_URL/" >/dev/null 2>&1; then
        echo "✅ CK is live!"
        break
    fi
    sleep 2
done

# Create a session via API
echo "📋 Creating hackathon session..."
SESSION=$(curl -sf -X POST "$CK_URL/api/v1/sessions" \
    -H "Content-Type: application/json" \
    -d '{
        "title": "GDG Stanford Hackathon — Governed Gemini Demo",
        "objective": "Demonstrate full ControlKeel governance with Gemini via AI Studio",
        "risk_tier": "moderate",
        "budget_cents": 3000
    }' 2>/dev/null || echo "{}")

SESSION_ID=$(echo "$SESSION" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session',{}).get('id',''))" 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
    echo "⚠️  Could not create session via API. CK web UI is still available at $CK_URL"
    echo "   Create a session manually via the web UI at $CK_URL/start"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 NEXT STEPS:"
echo ""
echo "1. Open $CK_URL in your browser"
echo "   → CK web UI: Mission Control, Findings, Proofs, Benchmarks"
echo ""
echo "2. Open Google AI Studio: https://aistudio.google.com"
echo "   → Create new agent"
echo "   → System Instructions: paste hackathon-demo/MASTER_PROMPT.md"
echo "   → Tools: upload hackathon-demo/functions.json"
echo ""
echo "3. Test: tell Gemini 'validate this code: eval(user_input)'"
echo "   → Gemini calls ck_validate → CK returns BLOCK → done"
echo ""
echo "4. Demo flow for judges: see hackathon-demo/DEMO_SCRIPT.md"
echo ""
