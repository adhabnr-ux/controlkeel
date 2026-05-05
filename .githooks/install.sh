#!/bin/bash
# Install ControlKeel governance hooks
# Run this script to install the git pre-commit hook

set -e

HOOKS_DIR=".githooks"
TARGET_DIR=".git/hooks"

echo "🔐 Installing ControlKeel governance hooks..."
echo ""

# Copy the pre-commit hook
if [ -f "$HOOKS_DIR/pre-commit" ]; then
    cp "$HOOKS_DIR/pre-commit" "$TARGET_DIR/pre-commit"
    chmod +x "$TARGET_DIR/pre-commit"
    echo "✅ Installed pre-commit hook"
else
    echo "❌ Error: pre-commit hook not found in $HOOKS_DIR"
    exit 1
fi

echo ""
echo "✅ Governance hooks installed successfully"
echo ""
echo "The pre-commit hook will now enforce governance state checks before commits."
echo "To bypass (NOT RECOMMENDED): touch .ck-session-governed"