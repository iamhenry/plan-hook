# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Hook System Architecture

This is an event-driven hook system that automatically generates and maintains implementation plans during Claude Code sessions. The system operates through three interconnected bash scripts that monitor tool usage patterns.

### Core Components and Data Flow

**plan-hook.sh** (Plan Capture)
- Triggers on `exit_plan_mode` tool usage
- Captures plan content from JSON stdin using jq
- Stores data in transcript for later processing
- Does NOT generate files immediately - only captures data

**file-modification-hook.sh** (Implementation Detection)  
- Triggers on Write/Edit/MultiEdit tools
- Detects when implementation begins (user accepted plan)
- Creates basic plan.md only if it doesn't exist
- Acts as minimal placeholder for TodoWrite enhancement

**todowrite-hook.sh** (Main Orchestrator)
- Triggers on TodoWrite tool usage
- Generates comprehensive plans with Claude CLI integration
- Maintains real-time status synchronization
- Handles incremental updates vs full regeneration logic

### Critical Workflow Patterns

The system follows a progressive enhancement pattern:
1. Plan content captured from `exit_plan_mode` → stored in transcript
2. File modifications detected → basic plan.md created  
3. TodoWrite tasks created → enhanced plan.md generated via Claude CLI

### Key Data Processing

**Input Sources:**
- Hook JSON data via stdin and `CLAUDE_TOOL_PARAMS` environment variable
- Transcript files for plan content extraction (last 50 lines for performance)
- Command line arguments as fallback mechanism

**State Management:**
- Plan.md existence indicates system state
- Task status mapping: pending→⏳, in_progress→🚧, completed→✅
- Incremental updates for status-only changes
- Full regeneration when 3+ todos with 2+ high priority detected

**File Operations:**
- Hardcoded path: `/Users/henry/Desktop/Projects/Tools/plan-hook/plan.md`
- Atomic operations with .bak cleanup
- Base64 encoding for complex JSON data handling

### Integration Points

**Claude CLI Integration:**
- Enhanced plan generation: `claude --model sonnet --print`
- Fallback templates when CLI unavailable
- Junior-developer-friendly content generation

**Configuration:**
- `.claude/settings.json`: Default plan mode configuration
- `.claude/settings.local.json`: Bash command permissions (ls, find, grep, diff, mkdir)

### Development Commands

**Testing Hooks:**
```bash
# Test plan capture (simulates exit_plan_mode)
echo '{"plan": "Test plan content"}' | ./plan-hook.sh

# Test file modification detection  
echo '{"tool": "Write", "file_path": "/test/file.js"}' | ./file-modification-hook.sh

# Test TodoWrite processing
echo '{"todos": [{"content": "Test task", "status": "pending", "priority": "high"}]}' | ./todowrite-hook.sh
```

**Debugging:**
```bash
# Check hook execution logs
cat /dev/stderr

# Verify plan.md generation
cat plan.md

# Test Claude CLI integration
claude --model sonnet --print "Generate a test plan"
```

### Architecture Considerations

**Error Handling Patterns:**
- Multiple fallback mechanisms for JSON parsing (jq → grep/sed)
- Graceful degradation when dependencies unavailable
- Comprehensive stderr logging for debugging

**Performance Optimization:**
- Fast path processing (transcript tail -50)
- Targeted tool execution permissions
- Minimal resource usage with event-driven design

**Status Synchronization:**
- Bidirectional consistency between TodoWrite and plan.md
- Visual status indicators must match task states
- Incremental updates preserve existing content structure

When working with this system, understand that it operates through automated event detection rather than manual triggers. The hooks maintain project planning state automatically while preserving natural Claude Code workflow patterns.