#!/bin/bash

# Plan Hook - Generates plan.md when exit_plan_mode tool is used
# This script is triggered by Claude Code's PreToolUse hook

# Read JSON data from stdin (how Claude Code passes hook data)
if [[ ! -t 0 ]]; then
    HOOK_DATA=$(cat)
else
    echo "No hook data received via stdin" >&2
    exit 0
fi

# Debug logging
echo "Exit plan mode hook triggered: $(date)" >&2
echo "Hook data: $HOOK_DATA" >&2

# Extract plan content from tool input JSON
if command -v jq >/dev/null 2>&1; then
    PLAN_CONTENT=$(echo "$HOOK_DATA" | jq -r '.tool_input.plan // empty')
else
    # Fallback parsing without jq
    PLAN_CONTENT=$(echo "$HOOK_DATA" | grep -o '"plan":"[^"]*"' | sed 's/"plan":"//; s/"$//')
fi

# Check if we successfully extracted plan content
if [[ -z "$PLAN_CONTENT" || "$PLAN_CONTENT" == "null" ]]; then
    echo "Warning: Could not extract plan content from tool parameters" >&2
    exit 0
fi

# No temp file needed - TodoWrite hook will read from transcript

# Create simple plan.md with timestamp (will be enhanced by TodoWrite hook)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
cat > plan.md << EOF
# Plan Captured: $TIMESTAMP

$PLAN_CONTENT

---
*Plan content captured by exit_plan_mode hook. Will be formatted by TodoWrite hook.*
EOF

echo "✅ Captured plan content: $PLAN_CONTENT" >&2
echo "✅ Created initial plan.md - TodoWrite hook will read from transcript" >&2