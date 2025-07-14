#!/bin/bash

# File Modification Hook - Detects plan acceptance via file modification tools (Write/Edit/MultiEdit)
# This script triggers on PreToolUse for Write, Edit, and MultiEdit tools

# Function to extract plan content from transcript file
extract_plan_from_transcript() {
    local transcript_path="$1"
    
    # Validate input
    if [[ ! -f "$transcript_path" ]]; then
        echo "Error: Transcript file not found: $transcript_path" >&2
        return 1
    fi
    
    # Fast path: last 50 lines (covers most cases)
    local plan_content=$(tail -50 "$transcript_path" | grep "exit_plan_mode" | tail -1 | jq -r '.tool_input.plan // empty' 2>/dev/null)
    
    # Fallback: entire file if not found in last 50 lines
    if [[ -z "$plan_content" ]]; then
        plan_content=$(grep "exit_plan_mode" "$transcript_path" | tail -1 | jq -r '.tool_input.plan // empty' 2>/dev/null)
    fi
    
    echo "$plan_content"
}

# Check if plan.md already exists
PLAN_FILE="/Users/henry/Desktop/Projects/Tools/plan-hook/plan.md"

if [[ -f "$PLAN_FILE" ]]; then
    echo "Plan.md already exists - no action needed" >&2
    exit 0
fi

# Plan.md doesn't exist and file modification is about to start
# This indicates user has accepted the plan and implementation is beginning

echo "File modification detected - generating plan.md (plan acceptance)" >&2

# Try to extract plan content from transcript
PLAN_CONTENT=""
TRANSCRIPT_PATH=$(echo "${CLAUDE_TOOL_PARAMS:-}" | jq -r '.transcript_path // empty' 2>/dev/null)

if [[ -n "$TRANSCRIPT_PATH" && "$TRANSCRIPT_PATH" != "empty" ]]; then
    PLAN_CONTENT=$(extract_plan_from_transcript "$TRANSCRIPT_PATH")
    echo "Found plan content from transcript" >&2
else
    # Look for transcript in common locations
    for potential_path in /tmp/claude-transcript.json ~/.claude/transcript.json ./transcript.json; do
        if [[ -f "$potential_path" ]]; then
            TRANSCRIPT_PATH="$potential_path"
            PLAN_CONTENT=$(extract_plan_from_transcript "$TRANSCRIPT_PATH")
            if [[ -n "$PLAN_CONTENT" ]]; then
                echo "Found plan content from: $potential_path" >&2
                break
            fi
        fi
    done
fi

# Generate basic plan.md if we have content
if [[ -n "$PLAN_CONTENT" ]]; then
    # Extract plan title (first line or default)
    PLAN_TITLE=$(echo "$PLAN_CONTENT" | head -1 | sed 's/^## \|^# \|^\* \|^- \|^[0-9]*\. //')
    if [[ -z "$PLAN_TITLE" ]]; then
        PLAN_TITLE="Implementation Plan"
    fi
    
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$PLAN_FILE" << EOF
# $PLAN_TITLE

## Overview
$(echo "$PLAN_CONTENT" | tail -n +2 | head -3)

## Implementation Started
File modification detected - implementation has begun.

---
*Generated: $TIMESTAMP when file modification started*
*Plan will be enhanced by TodoWrite hook when tasks are created*
EOF
    
    echo "✅ Generated plan.md from transcript content" >&2
else
    # Fallback - create minimal plan.md
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$PLAN_FILE" << EOF
# Implementation Plan

## Overview
Plan acceptance detected via file modification.
Implementation has begun.

---
*Generated: $TIMESTAMP when file modification started*
*Plan will be enhanced by TodoWrite hook when tasks are created*
EOF
    
    echo "✅ Generated minimal plan.md - no transcript content found" >&2
fi

echo "✅ Plan.md created - ready for TodoWrite hook to enhance" >&2