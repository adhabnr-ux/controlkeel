#!/bin/bash
# Governance Session Initialization Script
# Run this at the start of EVERY session to set up governance state

set -e

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(uuidgen 2>/dev/null || echo "manual-$(date +%s)")
GOVERNANCE_FILE=".ck-session-governed"
CHECKLIST_FILE=".session-start-checklist.md"

echo "🔐 ControlKeel Governance Session Initialization"
echo "=============================================="
echo ""

# Check if MCP tools are available
check_mcp_tools() {
    if command -v mcp_call_tool &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Try to call ck_context if MCP is available
if check_mcp_tools; then
    echo "✅ MCP tools available"
    echo ""
    echo "Step 1: Loading governed state with ck_context..."
    # This would be called by the host's MCP interface
    echo "   (Host should call ck_context via MCP)"
    echo ""
else
    echo "⚠️  MCP tools not directly available"
    echo "   Host must call ck_context via its MCP interface"
    echo ""
fi

# Check risk tier
check_risk_tier() {
    if [ -f "controlkeel/project.json" ]; then
        RISK=$(grep -o '"risk_tier":"[^"]*"' controlkeel/project.json 2>/dev/null | cut -d'"' -f4)
        if [ -n "$RISK" ]; then
            echo "📊 Risk Tier: $RISK"
            if [ "$RISK" = "critical" ]; then
                echo "   ⚠️  CRITICAL RISK - Strict governance required"
            fi
        fi
    fi
}

check_risk_tier
echo ""

# Check findings count
check_findings() {
    if [ -f "controlkeel/project.json" ]; then
        FINDINGS=$(grep -o '"active_findings":{[^}]*' controlkeel/project.json 2>/dev/null | grep -o '"count":[0-9]*' | cut -d':' -f2)
        BLOCKED=$(grep -o '"active_findings":{[^}]*' controlkeel/project.json 2>/dev/null | grep -o '"blocked":[0-9]*' | cut -d':' -f2)
        if [ -n "$FINDINGS" ]; then
            echo "📋 Active Findings: $FINDINGS (Blocked: $BLOCKED)"
        fi
    fi
}

check_findings
echo ""

# Create governance state file
create_governance_file() {
    cat > "$GOVERNANCE_FILE" << EOF
{
  "governed_at": "$TIMESTAMP",
  "session_id": "$SESSION_ID",
  "host": "$HOSTNAME",
  "user": "$USER",
  "risk_tier": "$(check_risk_tier 2>/dev/null | grep -o 'Risk Tier: [^ ]*' | cut -d' ' -f3 || echo 'unknown')",
  "mcp_available": $(check_mcp_tools && echo "true" || echo "false")
}
EOF
    echo "✅ Created governance state file: $GOVERNANCE_FILE"
}

create_governance_file
echo ""

# Show checklist
echo "📝 Next Steps:"
echo "-------------"
echo "1. Review the session start checklist:"
echo "   cat $CHECKLIST_FILE"
echo ""
echo "2. If MCP tools are available, call:"
echo "   - ck_context (to load governed state)"
echo "   - controlkeel-governance skill (to activate governance)"
echo "   - ck_budget (to check budget)"
echo ""
echo "3. Before making changes, call:"
echo "   - ck_validate (to validate code/config/shell/deploy)"
echo ""
echo "4. Record decisions with:"
echo "   - ck_memory_record (for important decisions)"
echo "   - ck_finding (for issues discovered)"
echo ""

# Show governance log location
echo "📊 Governance log: .governance-log.txt"
echo ""
echo "✅ Session initialization complete"
echo ""
echo "Remember: Every session requires fresh governance invocation!"