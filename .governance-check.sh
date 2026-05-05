#!/bin/bash
# Governance Pre-Flight Check
# This script enforces ControlKeel governance protocols before allowing code changes
# Usage: .governance-check.sh [file_or_command]

set -e

GOVERNANCE_LOG=".governance-log.txt"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log() {
    echo "[$TIMESTAMP] $1" >> "$GOVERNANCE_LOG"
}

# Check if this is a new session (no governance state in current session)
check_governance_state() {
    if [ ! -f ".ck-session-governed" ]; then
        log "GOVERNANCE VIOLATION: No governance state file found"
        echo "❌ GOVERNANCE ERROR: This session has not been governed"
        echo ""
        echo "Before making any changes, you must:"
        echo "  1. Call ck_context to load session state"
        echo "  2. Invoke controlkeel-governance skill"
        echo "  3. Check budget with ck_budget"
        echo "  4. Validate plans with ck_review_submit"
        echo ""
        echo "Create .ck-session-governed file after completing governance setup"
        return 1
    fi
    return 0
}

# Check if changes are being made
check_pending_changes() {
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        log "Pending git changes detected"
        return 0
    fi
    return 1
}

# Check for critical risk session
check_risk_tier() {
    if [ -f "controlkeel/project.json" ]; then
        RISK=$(grep -o '"risk_tier":"[^"]*"' controlkeel/project.json 2>/dev/null || echo "unknown")
        if echo "$RISK" | grep -q "critical"; then
            log "CRITICAL risk session detected"
            echo "⚠️  CRITICAL RISK SESSION - Strict governance required"
            return 0
        fi
    fi
    return 1
}

# Main check
main() {
    log "Governance pre-flight check initiated"

    # Check governance state
    if ! check_governance_state; then
        exit 1
    fi

    # Check risk tier
    check_risk_tier

    # If files are being changed, require validation
    if check_pending_changes; then
        log "Pending changes require validation"
        echo "⚠️  Pending changes detected - ensure ck_validate was called"
    fi

    log "Governance pre-flight check passed"
    return 0
}

main "$@"