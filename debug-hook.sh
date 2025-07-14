#!/bin/bash

# Debug hook to see what environment variables Claude Code provides
LOG_FILE="/Users/henry/Desktop/Projects/Tools/plan-hook/hook-debug.log"

echo "=== Claude Code Hook Debug ===" >&2
echo "Hook triggered at $(date)" >&2

# Log to file for persistence
{
    echo "$(date): Hook triggered"
    echo "CLAUDE_TOOL_NAME: ${CLAUDE_TOOL_NAME:-not_set}"
    echo "CLAUDE_TOOL_PARAMS: ${CLAUDE_TOOL_PARAMS:-not_set}"
    echo "All CLAUDE/TOOL vars:"
    env | grep -E "(CLAUDE|TOOL)" || echo "No CLAUDE/TOOL vars found"
    echo "---"
} >> "$LOG_FILE"

echo "Debug logged to $LOG_FILE" >&2