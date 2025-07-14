#!/bin/bash

# TodoWrite Hook - Detects plan execution start via TodoWrite patterns
LOG_FILE="/Users/henry/Desktop/Projects/Tools/plan-hook/todowrite-debug.log"

# Function to extract plan content from transcript file
extract_plan_from_transcript() {
    local transcript_path="$1"
    
    # Validate input
    if [[ ! -f "$transcript_path" ]]; then
        echo "Error: Transcript file not found: $transcript_path" >> "$LOG_FILE"
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

# Function to detect if changes are status-only
is_status_only_change() {
    local tool_params="$1"
    
    # Extract old and new todos from tool_response
    local old_todos=$(echo "$tool_params" | jq -r '.tool_response.oldTodos // [] | map({content, priority, id}) | sort_by(.id)' 2>/dev/null)
    local new_todos=$(echo "$tool_params" | jq -r '.tool_response.newTodos // [] | map({content, priority, id}) | sort_by(.id)' 2>/dev/null)
    
    # If we can't parse JSON, assume structural change
    if [[ -z "$old_todos" || -z "$new_todos" || "$old_todos" == "null" || "$new_todos" == "null" ]]; then
        echo "false"
        return 0
    fi
    
    # Compare content, priority, and id fields (excluding status)
    if [[ "$old_todos" == "$new_todos" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to update checkboxes based on task status
update_task_checkboxes() {
    local plan_file="$1"
    local task_content="$2"
    local task_status="$3"
    
    # Escape special characters in task content for sed
    local escaped_content=$(echo "$task_content" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    # Find the task section and extract all checkbox lines
    local task_section_start=$(grep -n "### .* Task.*: $escaped_content" "$plan_file" | head -1 | cut -d: -f1)
    local task_section_end=$(tail -n +$((task_section_start + 1)) "$plan_file" | grep -n "^### " | head -1 | cut -d: -f1)
    
    if [[ -z "$task_section_start" ]]; then
        echo "Could not find task section for: $task_content" >> "$LOG_FILE"
        return 1
    fi
    
    # Calculate the actual end line number
    if [[ -n "$task_section_end" ]]; then
        task_section_end=$((task_section_start + task_section_end - 1))
    else
        task_section_end=$(wc -l < "$plan_file")
    fi
    
    # Extract checkbox lines from the task section
    local checkbox_lines=$(sed -n "${task_section_start},${task_section_end}p" "$plan_file" | grep -n "^- \[\|^  - \[" | cut -d: -f1)
    
    if [[ -z "$checkbox_lines" ]]; then
        echo "No checkboxes found in task section: $task_content" >> "$LOG_FILE"
        return 0
    fi
    
    # Count total checkboxes
    local total_checkboxes=$(echo "$checkbox_lines" | wc -l)
    local halfway_point=$((total_checkboxes / 2))
    
    # Update checkboxes based on status
    local line_count=0
    for relative_line in $checkbox_lines; do
        line_count=$((line_count + 1))
        local actual_line=$((task_section_start + relative_line - 1))
        
        case "$task_status" in
            "completed")
                # All checkboxes checked
                sed -i.bak "${actual_line}s/^- \[ \]/- [x]/" "$plan_file"
                sed -i.bak "${actual_line}s/^  - \[ \]/  - [x]/" "$plan_file"
                ;;
            "in_progress")
                # First half checked, second half unchecked
                if [[ $line_count -le $halfway_point ]]; then
                    sed -i.bak "${actual_line}s/^- \[ \]/- [x]/" "$plan_file"
                    sed -i.bak "${actual_line}s/^  - \[ \]/  - [x]/" "$plan_file"
                else
                    sed -i.bak "${actual_line}s/^- \[x\]/- [ ]/" "$plan_file"
                    sed -i.bak "${actual_line}s/^  - \[x\]/  - [ ]/" "$plan_file"
                fi
                ;;
            "pending")
                # All checkboxes unchecked
                sed -i.bak "${actual_line}s/^- \[x\]/- [ ]/" "$plan_file"
                sed -i.bak "${actual_line}s/^  - \[x\]/  - [ ]/" "$plan_file"
                ;;
        esac
    done
    
    rm -f "$plan_file.bak"
    echo "Updated $total_checkboxes checkboxes for task: $task_content -> $task_status" >> "$LOG_FILE"
    return 0
}

# Function to update only task statuses in existing plan.md
update_task_statuses() {
    local tool_params="$1"
    local plan_file="/Users/henry/Desktop/Projects/Tools/plan-hook/plan.md"
    
    # Extract new todos with status
    local new_todos=$(echo "$tool_params" | jq -r '.tool_response.newTodos // []' 2>/dev/null)
    
    if [[ -z "$new_todos" || "$new_todos" == "null" ]]; then
        echo "Failed to parse new todos for status update" >> "$LOG_FILE"
        return 1
    fi
    
    # Update each task status
    echo "$new_todos" | jq -r '.[] | @base64' | while read -r task_data; do
        local task_content=$(echo "$task_data" | base64 -d | jq -r '.content // empty')
        local task_status=$(echo "$task_data" | base64 -d | jq -r '.status // empty')
        
        if [[ -n "$task_content" && -n "$task_status" ]]; then
            # Map status to emoji
            local status_emoji status_text
            case "$task_status" in
                "completed") status_emoji="✅"; status_text="COMPLETED" ;;
                "in_progress") status_emoji="🚧"; status_text="IN PROGRESS" ;;
                *) status_emoji="⏳"; status_text="PENDING" ;;
            esac
            
            # Update task section in plan.md
            if grep -q "Task.*: $task_content" "$plan_file" 2>/dev/null; then
                # Escape special characters in task content for sed
                local escaped_content=$(echo "$task_content" | sed 's/[[\.*^$()+?{|]/\\&/g')
                
                # Update emoji in task header
                sed -i.bak "s/### [⏳🚧✅] Task.*: $escaped_content/### $status_emoji Task.*: $escaped_content/" "$plan_file"
                # Update status line
                sed -i.bak "/### $status_emoji Task.*: $escaped_content/,/^### / s/Status: .*/Status: $status_text/" "$plan_file"
                rm -f "$plan_file.bak"
                
                # Update checkboxes based on task status
                update_task_checkboxes "$plan_file" "$task_content" "$task_status"
                
                echo "Updated task: $task_content -> $status_text" >> "$LOG_FILE"
            fi
        fi
    done
    
    echo "✅ Updated task statuses in plan.md" >> "$LOG_FILE"
    return 0
}

# Log all TodoWrite activity and environment variables
{
    echo "=== TodoWrite Hook Triggered: $(date) ==="
    echo "CLAUDE_TOOL_NAME: ${CLAUDE_TOOL_NAME:-not_set}"
    echo "CLAUDE_TOOL_PARAMS: ${CLAUDE_TOOL_PARAMS:-not_set}"
    echo "All environment variables with CLAUDE or TOOL:"
    env | grep -i -E "(claude|tool)" || echo "No CLAUDE/TOOL env vars found"
    echo "Command line arguments: $*"
    echo "---"
} >> "$LOG_FILE"

# Basic plan detection - look for multiple high priority todos
# Try to get tool params from environment variable, command line args, or stdin
TOOL_PARAMS=""
if [[ -n "$CLAUDE_TOOL_PARAMS" && "$CLAUDE_TOOL_PARAMS" != "not_set" ]]; then
    TOOL_PARAMS="$CLAUDE_TOOL_PARAMS"
elif [[ $# -gt 0 ]]; then
    TOOL_PARAMS="$*"
elif [[ ! -t 0 ]]; then
    # Read from stdin if available
    TOOL_PARAMS=$(cat)
fi

if [[ -n "$TOOL_PARAMS" ]]; then
    # Count todos and check for patterns
    TODO_COUNT=$(echo "$TOOL_PARAMS" | grep -o '"content"' | wc -l)
    HIGH_PRIORITY=$(echo "$TOOL_PARAMS" | grep -o '"priority":"high"' | wc -l)
    IN_PROGRESS=$(echo "$TOOL_PARAMS" | grep -o '"status":"in_progress"' | wc -l)
    
    {
        echo "Using tool params: $TOOL_PARAMS"
        echo "Todo count: $TODO_COUNT"
        echo "High priority: $HIGH_PRIORITY" 
        echo "In progress: $IN_PROGRESS"
    } >> "$LOG_FILE"
    
    # Check if plan.md exists and if this is a status-only change
    PLAN_FILE="/Users/henry/Desktop/Projects/Tools/plan-hook/plan.md"
    if [[ -f "$PLAN_FILE" && $(is_status_only_change "$TOOL_PARAMS") == "true" ]]; then
        echo "Status-only change detected - performing incremental update" >> "$LOG_FILE"
        
        # Perform incremental update
        if update_task_statuses "$TOOL_PARAMS"; then
            echo "✅ Incremental update completed successfully" >> "$LOG_FILE"
            exit 0
        else
            echo "⚠️  Incremental update failed, falling back to full regeneration" >> "$LOG_FILE"
            # Fall through to full regeneration
        fi
    fi
    
    # Full regeneration logic: 3+ todos with high priority suggests plan execution start
    if [[ $TODO_COUNT -ge 3 && $HIGH_PRIORITY -ge 2 ]]; then
        echo "Plan execution detected - generating enhanced plan.md" >> "$LOG_FILE"
        
        # Extract plan content from transcript file
        PLAN_CONTENT=""
        TRANSCRIPT_PATH=$(echo "$TOOL_PARAMS" | jq -r '.transcript_path // empty' 2>/dev/null)
        
        if [[ -n "$TRANSCRIPT_PATH" && "$TRANSCRIPT_PATH" != "empty" ]]; then
            PLAN_CONTENT=$(extract_plan_from_transcript "$TRANSCRIPT_PATH")
            echo "Found plan content from transcript: $PLAN_CONTENT" >> "$LOG_FILE"
        else
            echo "No transcript path found in tool params" >> "$LOG_FILE"
        fi
        
        # Extract plan title (first line or default)
        PLAN_TITLE="Implementation Plan"
        if [[ -n "$PLAN_CONTENT" ]]; then
            PLAN_TITLE=$(echo "$PLAN_CONTENT" | head -1 | sed 's/^## \|^# \|^\* \|^- \|^[0-9]*\. //')
            if [[ -z "$PLAN_TITLE" ]]; then
                PLAN_TITLE="Implementation Plan"
            fi
        fi
        
        # Generate enhanced plan.md using Claude integration
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Read template content for Claude prompt
        TEMPLATE_CONTENT=""
        if [[ -f "/Users/henry/Desktop/Projects/Tools/plan-hook/plan-task-template.md" ]]; then
            TEMPLATE_CONTENT=$(cat "/Users/henry/Desktop/Projects/Tools/plan-hook/plan-task-template.md")
        fi
        
        # Construct comprehensive Claude prompt
        CLAUDE_PROMPT="FORMATTING GUIDE:
$TEMPLATE_CONTENT

PLAN CONTEXT:
$PLAN_CONTENT

CURRENT TASKS (TodoWrite JSON):
$TOOL_PARAMS

INSTRUCTIONS:
Generate a complete plan.md file that:
1. Follows the exact structure from the formatting guide
2. Uses the plan context for overview and task understanding  
3. Maps TodoWrite tasks to detailed implementation steps
4. Includes junior-developer-friendly details, file modifications, dependencies, and testing strategies
5. Generates appropriate sub-tasks based on task content (not generic ones)
6. Maintains current task status from TodoWrite data

Output only the complete plan.md content, no explanations."

        # Fallback function for basic template generation
        generate_basic_plan() {
            cat > /Users/henry/Desktop/Projects/Tools/plan-hook/plan.md << EOF
# $PLAN_TITLE

## Overview
$(if [[ -n "$PLAN_CONTENT" ]]; then
    echo "$PLAN_CONTENT" | tail -n +2 | head -3
else
    echo "Plan execution detected via TodoWrite hook with $TODO_COUNT tasks."
    echo "Implementation progress tracking with structured task management."
fi)

## Tasks
EOF

            # Parse and format tasks from TodoWrite JSON using template structure
            TASK_NUM=1
            echo "$TOOL_PARAMS" | grep -o '"content":"[^"]*","status":"[^"]*","priority":"[^"]*"' | while read -r task_data; do
                TASK_CONTENT=$(echo "$task_data" | sed 's/.*"content":"\([^"]*\)".*/\1/')
                TASK_STATUS=$(echo "$task_data" | sed 's/.*"status":"\([^"]*\)".*/\1/')
                TASK_PRIORITY=$(echo "$task_data" | sed 's/.*"priority":"\([^"]*\)".*/\1/')
                
                # Map status to emoji following template format
                case "$TASK_STATUS" in
                    "completed") EMOJI="✅" STATUS_TEXT="COMPLETED" ;;
                    "in_progress") EMOJI="🚧" STATUS_TEXT="IN PROGRESS" ;;
                    *) EMOJI="⏳" STATUS_TEXT="PENDING" ;;
                esac
                
                # Generate status-based checkboxes
                generate_checkboxes() {
                    local status="$1"
                    case "$status" in
                        "completed")
                            echo "- [x] Review task requirements"
                            echo "- [x] Implement solution"
                            echo "- [x] Test functionality"
                            echo "- [x] Update documentation"
                            ;;
                        "in_progress")
                            echo "- [x] Review task requirements"
                            echo "- [x] Implement solution"
                            echo "- [ ] Test functionality"
                            echo "- [ ] Update documentation"
                            ;;
                        *)
                            echo "- [ ] Review task requirements"
                            echo "- [ ] Implement solution"
                            echo "- [ ] Test functionality"
                            echo "- [ ] Update documentation"
                            ;;
                    esac
                }
                
                cat >> /Users/henry/Desktop/Projects/Tools/plan-hook/plan.md << EOF

### $EMOJI Task $TASK_NUM: $TASK_CONTENT
Status: $STATUS_TEXT
Priority: $(echo "$TASK_PRIORITY" | tr '[:lower:]' '[:upper:]')
Details: Implementation task tracked via TodoWrite system
$(generate_checkboxes "$TASK_STATUS")
Dependencies: Previous tasks as applicable
Testing Strategy: Verify completion criteria
EOF
                ((TASK_NUM++))
            done
            
            # Add footer with metadata
            cat >> /Users/henry/Desktop/Projects/Tools/plan-hook/plan.md << EOF

---
*Generated: $TIMESTAMP using template structure*
*Last Update: $(date)*
*Total Tasks: $TODO_COUNT | High Priority: $HIGH_PRIORITY | In Progress: $IN_PROGRESS*
EOF
        }

        # Call Claude to generate plan (with fallback to basic template)
        if command -v claude >/dev/null 2>&1; then
            echo "Calling Claude to generate enhanced plan.md..." >> "$LOG_FILE"
            if echo "$CLAUDE_PROMPT" | claude --model sonnet --print > /Users/henry/Desktop/Projects/Tools/plan-hook/plan.md 2>>"$LOG_FILE"; then
                echo "✅ Generated enhanced plan.md with Claude" >> "$LOG_FILE"
            else
                echo "⚠️  Claude generation failed, falling back to basic template" >> "$LOG_FILE"
                # Fallback to basic template (existing logic as backup)
                generate_basic_plan
            fi
        else
            echo "⚠️  Claude CLI not available, using basic template" >> "$LOG_FILE"
            # Fallback to basic template
            generate_basic_plan
        fi
        
        echo "✅ Generated enhanced plan.md with template structure" >> "$LOG_FILE"
    fi
fi