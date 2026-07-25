#!/usr/bin/env bash
# scripts/self_host_smoke.sh
#
# Boot the Phoenix endpoint with a non-canonical PHX_HOST (self_hosted runtime
# mode) against a fresh SQLite DB. Assert the home page responds and the
# /cloud/v1/workspaces/register endpoint is mounted. Tear down cleanly.
#
# Used by .github/workflows/ci.yml (self-host-smoke job) and by self-hosters
# who want to validate their environment before `fly deploy`.

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────

export MIX_ENV="${MIX_ENV:-dev}"
export PHX_HOST="${PHX_HOST:-govern.selfhost.test}"
export CONTROLKEEL_RUNTIME_MODE="${CONTROLKEEL_RUNTIME_MODE:-self_hosted}"
export PORT="${PORT:-4099}"
export PHX_SERVER="${PHX_SERVER:-true}"

# Per-run scratch state — never reuse a global dir
TMP_DB="$(mktemp -t ck_selfhost_smoke.XXXXXX.db)"
TMP_HOME="$(mktemp -d -t ck_selfhost_home_XXXXXX)"
export DATABASE_PATH="$TMP_DB"
export CONTROLKEEL_HOME="$TMP_HOME"

# Generate a secret key if not already set
if [[ -z "${SECRET_KEY_BASE:-}" ]]; then
  export SECRET_KEY_BASE="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | base64)"
fi

SERVER_PID=""

# ── Cleanup ─────────────────────────────────────────────────────────

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    # Give it a moment to shut down gracefully
    for _ in 1 2 3 4 5; do
      kill -0 "$SERVER_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$TMP_DB" 2>/dev/null || true
  rm -rf "$TMP_HOME" 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. Migrations on a fresh DB ─────────────────────────────────────

echo "▶ Self-host smoke: PHX_HOST=$PHX_HOST RUNTIME_MODE=$CONTROLKEEL_RUNTIME_MODE PORT=$PORT"
echo "▶ DB: $DATABASE_PATH"

mix ecto.create -r ControlKeel.Repo.Local >/dev/null
mix ecto.migrate -r ControlKeel.Repo.Local >/dev/null

# ── 2. Boot the Phoenix endpoint ────────────────────────────────────

mix phx.server >/tmp/ck_selfhost_smoke.log 2>&1 &
SERVER_PID=$!

# Wait up to 60s for the home page to respond
booted=0
for i in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    echo "✅ Home page responds at http://127.0.0.1:${PORT}/ after ${i}s"
    booted=1
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ Server died during boot. Tail of log:" >&2
    tail -50 /tmp/ck_selfhost_smoke.log >&2 || true
    exit 1
  fi
  sleep 1
done

if [[ $booted -ne 1 ]]; then
  echo "❌ Server did not bind to PORT $PORT within 60s. Tail of log:" >&2
  tail -50 /tmp/ck_selfhost_smoke.log >&2 || true
  exit 1
fi

# ── 3. Enrollment endpoint mounted ──────────────────────────────────

# POST /cloud/v1/workspaces/register with an empty body must be rejected with
# a 4xx (the endpoint runs through Cloud.Enrollment.verify, which rejects
# malformed envelopes). We accept 400, 401, 422 — anything in that range
# proves the endpoint is mounted; 404 would mean the route never registered.
status="$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "content-type: application/json" \
  -d '{}' \
  "http://127.0.0.1:${PORT}/cloud/v1/workspaces/register")"

case "$status" in
  400|401|422)
    echo "✅ Enrollment endpoint mounted (HTTP $status on empty body)"
    ;;
  *)
    echo "❌ Expected 400/401/422 from /cloud/v1/workspaces/register, got $status" >&2
    exit 1
    ;;
esac

# ── 4. Sync endpoint requires Bearer (CloudWorkspaceKeyAuth pipeline) ─

status="$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "content-type: application/json" \
  -d '{}' \
  "http://127.0.0.1:${PORT}/cloud/v1/sync/push")"

if [[ "$status" != "401" ]]; then
  echo "❌ Expected 401 from /cloud/v1/sync/push without Bearer, got $status" >&2
  exit 1
fi
echo "✅ Sync endpoint protected by CloudWorkspaceKeyAuth (HTTP $status)"

echo ""
echo "🎉 Self-host smoke passed."
