# Plan Hook Implementation TODO

## Core Hook Script Development
- [ ] Create `scripts/plan_hook.sh` with three main modes (mark_plan_presented, check_and_init, update)
- [ ] Remove finalize mode (archiving built into update mode)
- [ ] Implement plan extraction logic to parse task lists from Claude's conversation transcript
- [ ] Add task completion tracking using emoji status format (⏳ → 🚧 → ✅)
- [ ] Build archive system with timestamp and project description extraction
- [ ] Add comprehensive error handling and graceful degradation
- [ ] Make script executable and test basic functionality

## Template and Configuration
- [ ] Use existing `plan-task-template.md` as reference guide for plan.md structure
- [ ] Implement template structure with emoji headers (⏳🚧✅) and sub-task checkboxes
- [ ] Create `.claude/settings.json` with PostToolUse for exit_plan_mode and PreToolUse + PostToolUse for work tools
- [ ] Configure tool matchers for Edit, Write, MultiEdit, Bash, and NotebookEdit tools
- [ ] Remove Stop hook configuration (archiving happens on task completion)
- [ ] Set up proper hook command paths and arguments

## Directory Structure and Setup
- [ ] Create `scripts/` directory for hook scripts
- [ ] Create `archives/` directory for completed plans (following `/_ai/completed-plans/` pattern from template)
- [ ] Ensure all directories have proper permissions
- [ ] Add `.gitignore` entries for generated plan.md files if needed

## Plan Extraction and Processing
- [ ] Implement plan presentation detection in mark_plan_presented mode
- [ ] Store plan content temporarily when exit_plan_mode triggers
- [ ] Extract numbered/bulleted task lists in check_and_init mode
- [ ] Handle various task list formats (1., 2., -, •, etc.)
- [ ] Convert extracted tasks to plan-task-template.md format with emoji headers
- [ ] Extract project description from plan title/heading for archive naming
- [ ] Add fallback logic for malformed or missing task lists

## Task Completion Tracking
- [ ] Implement sequential task status updates (⏳ → 🚧 → ✅)
- [ ] Mark tasks as IN PROGRESS when PostToolUse hook triggers
- [ ] Update sub-task checkboxes within task sections
- [ ] Handle edge cases like non-plan tool usage between tasks
- [ ] Add optional task content matching for accuracy

## Archive System
- [ ] Implement completion detection within update mode (all tasks marked ✅)
- [ ] Generate timestamped archive filenames immediately when complete
- [ ] Extract meaningful project descriptions from plan content
- [ ] Move completed plan.md to `/archives/` with descriptive filename
- [ ] Ensure archive directory exists and is accessible
- [ ] Build archiving logic into update mode, not separate finalize mode

## Hook Integration and Testing
- [ ] Test PostToolUse hook on exit_plan_mode marks plan as presented
- [ ] Test PreToolUse hook on work tools generates plan.md when plan was presented
- [ ] Verify PostToolUse hook updates tasks after each tool completion
- [ ] Confirm immediate archiving when all tasks completed (no Stop hook needed)
- [ ] Test hook filtering to only trigger on relevant tools
- [ ] Validate hook execution permissions and environment

## Error Handling and Edge Cases
- [ ] Handle missing template files gracefully
- [ ] Deal with corrupted or incomplete plan.md files
- [ ] Manage archive directory creation failures
- [ ] Handle transcript parsing errors
- [ ] Add logging for debugging hook execution issues

## Documentation and Finalization
- [ ] Create setup instructions for hook configuration
- [ ] Document template customization options
- [ ] Add troubleshooting guide for common issues
- [ ] Create example usage scenarios
- [ ] Test complete workflow from plan creation to archive

## Validation and Quality Assurance
- [ ] Test with various plan formats and task structures
- [ ] Verify compatibility with different Claude Code versions
- [ ] Check hook performance impact on tool execution
- [ ] Validate file permissions and security considerations
- [ ] Test rollback scenarios and failure recovery