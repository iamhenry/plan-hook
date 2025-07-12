### Planning and Task Management

### Plan Documentation Protocol
When implementing complex features or multi-step tasks:
1. ALWAYS create a `plan.md` file in the project root
2. Structure tasks with sufficient detail for junior developers
3. Use recursive completion tracking as work progresses
4. Integrate with TodoWrite tool for active session management

#### Task Detail Requirements
Each task MUST include:
- Clear objective a junior developer can understand
- Step-by-step implementation guidance
- Expected file modifications
- Dependencies and prerequisites
- Testing strategy and acceptance criteria
- Time estimation where applicable

#### Progress Tracking Protocol
- Update task status immediately upon completion: ⏳ → 🚧 → ✅
- Mark sub-tasks with checkboxes for granular progress
- Add completion timestamps and notes
- Link to related TodoWrite entries for active session tracking
- Archive completed plan.md files to `/_ai/completed-plans/` directory

#### Integration with TodoWrite
- Create TodoWrite entries referencing specific plan.md tasks
- Use consistent task naming: "Plan.md: [Task Title]"
- Mark TodoWrite items complete when plan.md tasks are finished
- Maintain bidirectional traceability between tools

#### Plan.md Structure Template
```markdown
# [Feature/Task Name] Implementation Plan

## Overview
Brief description of what needs to be accomplished

## Tasks
### ✅ Task 1: [Completed task title]
Status: COMPLETED
Details: What a junior dev needs to know
- Sub-task 1
- Sub-task 2
Files Modified: list of files
Testing: How to verify completion

### 🚧 Task 2: [In progress task title]  
Status: IN PROGRESS
Details: Step-by-step instructions for implementation
- [ ] Sub-task 1
- [ ] Sub-task 2
- [x] Sub-task 3 (completed)
Dependencies: What must be done first
Files to Modify: Expected file changes
Testing Strategy: How to test this task

### ⏳ Task 3: [Pending task title]
Status: PENDING
Details: Clear implementation guidance
Dependencies: Task 2 completion
Acceptance Criteria: Definition of done
```