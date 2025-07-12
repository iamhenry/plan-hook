# Claude Code Hook for Auto-Generating and Managing `plan.md`

**Goal:** Use Claude Code’s hooks to automatically create a `plan.md` file when a plan is accepted, keep it updated as tasks complete, and archive it upon completion. This ensures the implementation plan (task list) is documented and tracked without relying on the AI alone.

## Plan Mode and Approval in Claude Code

Claude Code’s **Plan Mode** lets the assistant draft a detailed implementation plan (a structured to-do list of steps) without making changes. No edits or commands run until **you approve the plan**. Once you approve (by exiting plan mode), Claude proceeds to execution. We will leverage this transition point and subsequent tool usage events via hooks.

* **Plan Output:** In plan mode, Claude typically presents a numbered or bulleted list of tasks as the implementation plan. For example, it might say:
  *Creates todo list with the following items:*

  1. Create dark mode toggle component in settings page
  2. Add dark mode state management (context/store)
  3. Implement styling for dark theme …

* **User Acceptance:** After presenting the plan, Claude waits for your confirmation. Only after you approve does it start performing those tasks. We will trigger our hook at this point to generate `plan.md` from the plan.

## Required Hooks and Events

Claude Code supports **user-defined hooks** that run at specific lifecycle events. We'll use these hook events for this automation:

1. **PostToolUse on exit_plan_mode** – Runs *after* the `exit_plan_mode` tool completes, which happens when Claude presents a plan. We use this to mark that a plan was presented (but not yet approved).
2. **PreToolUse on work tools** – Runs *before* the first actual work tool executes. We check if a plan was presented AND no plan.md exists, then generate plan.md from the approved plan.
3. **PostToolUse on work tools** – Runs *after* task execution tools complete successfully. We'll hook this to update the to-do list in `plan.md` after each task and check for completion.
4. **Immediate archiving** – When all tasks are marked complete (✅), the plan is archived immediately during the update phase, not at session end.

These hooks give us reliable, automatic triggers in the CLI workflow, rather than relying on the AI to remember to update files. We will configure them in Claude’s settings so they execute deterministically at those points.

## Tools and Utilities Needed for the Hook Scripts

The hook actions will be implemented as shell commands or scripts. Key tools and capabilities we’ll need:

* **File I/O:** Read and write files on disk. The scripts will:

  * Read a custom Markdown template from a given `templatePath` (to guide plan formatting).
  * Create or update the `plan.md` file (path specified by `outputPlanPath`, e.g. `./plan.md` in project root).
  * Rename/move files for archiving (`fs.rename` or `mv` to an `archiveFolder`).
* **Text Processing:** Insert the dynamic task list into the template and mark tasks complete. This can be done with scripting languages (Bash, Python, Node.js, etc.) or utilities like `sed`/`awk` as needed.
* **Date/Time Utility:** Generate a timestamp string for archive filenames (e.g. using the `date` command or a library) to uniquely timestamp archived plans.
* **Environment Variables from Claude Code:** The CLI provides context to hook commands via env vars:

  * `$CLAUDE_EVENT_TYPE` – the event type (`PreToolUse`, `PostToolUse`, etc.).
  * `$CLAUDE_TOOL_NAME` – the name of the tool being run (e.g. `Edit`, `Write`, `Bash`). We can use this in a script to tailor behavior per tool.
  * `$CLAUDE_TOOL_INPUT` – JSON of the tool’s input parameters (e.g. file path, command). This could help identify specific actions, though for our purposes we mostly track task completion order.
  * `$CLAUDE_FILE_PATHS` – file paths involved (for file tools), useful if we want to log which file was edited for each task.

These will help our hooks logic decide what to do at runtime. For example, we might only generate `plan.md` if `$CLAUDE_TOOL_NAME` is one of the edit/write tools and the file doesn’t exist yet.

## Initial Plan Generation (`plan.md` Creation)

**Trigger:** After the user accepts the plan and Claude is about to execute the first real task. In practice, this corresponds to the **first PreToolUse** event for a modifying tool (e.g. an Edit or Write tool call on a file, or a Bash command if the first step is running a command). At that moment, we know the plan has just been approved and execution is starting.

**Hook Setup:** We configure a PreToolUse hook to catch this moment. We can filter by tool if desired (e.g. match only `Edit|Write|Bash`) so it runs on the first edit/write/command after plan mode. For example, in the project’s `.claude/settings.json` (or global settings), we add something like:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Edit|Write|Bash", 
      "hooks": [
        { "type": "command", "command": "./scripts/plan_hook.sh init" }
      ]
    }
  ]
}
```

This means **before** executing any Edit/Write/Bash, run our `plan_hook.sh init` script. (The above uses a regex matcher for simplicity – Claude hooks support regex or exact tool names.)

**Action:** The `init` mode of our hook script will:

* **Load the template** from `templatePath`. This template might contain static sections or placeholders (e.g. a header or format for the plan). For example, the template could have a section for introduction or instructions on how to use the plan, and a placeholder where the to-do list should go.
* **Extract the task list** from Claude’s proposed plan. Since Claude presented the tasks just before this point, the script can retrieve them. One method is to read the conversation transcript (path provided in the hook JSON input as `transcript_path`) and parse the last assistant message for the list of tasks. Typically, tasks are in a structured list format (numbered or bulleted) as shown above. The script can identify lines starting with `1.`, `2.`... or `- ` and collect them as the task list.

  * *Example:* If the plan output included:
    `1. Create dark mode toggle component...`
    `2. Add state management for dark mode...`
    `3. Run tests to verify...`
    the script will gather these three items as the tasks.
* **Insert tasks into the template:** Replace the placeholder or section in the template with the tasks. We can format them in Markdown as a checklist for easy tracking. For instance, convert to:
  `- [ ] Create dark mode toggle component in settings page`
  `- [ ] Add state management for dark mode`
  `- [ ] Run tests to verify functionality`
  All tasks start unchecked (`[ ]`). Section headings use status emojis (⏳🚧✅) while individual tasks use checkboxes. This will be the initial content in `plan.md`.
* **Write out `plan.md`:** Save the populated template to `outputPlanPath` (e.g. `./plan.md` in the repo). Now we have a file that lists all TODOs from the accepted plan.

By performing this when the first tool runs, we ensure `plan.md` is only created **after plan approval**, not during the planning phase. (Claude itself will not create such a file on its own – in fact, the system discourages the AI from writing docs unless asked, so using a hook is appropriate.)

**Verification:** If the user aborted or never approved the plan, this hook won’t run (since no execution tools run), so no `plan.md` will be created – which is the desired behavior.

## Auto-Updating `plan.md` as Tasks Complete

**Trigger:** After each task is executed successfully. We use a **PostToolUse** hook so it runs after Claude finishes a tool action (e.g. file edit or command). This way we only update the plan if the action was actually executed (and presumably the task is done).

**Hook Setup:** Configure PostToolUse for relevant tools that correspond to plan steps. Likely candidates: the file modification tools and certain bash commands. For example:

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Edit|Write|MultiEdit|Bash", 
      "hooks": [
        { "type": "command", "command": "./scripts/plan_hook.sh update" }
      ]
    }
  ]
}
```

This will call our script in “update” mode after any file edit/write or Bash command completes.

**Action:** The `update` logic will:

* **Open `plan.md`** and find the task list. Because we formatted tasks as a checklist, the script can find the first incomplete task (`- [ ] ...`) and mark it complete. For example, it can replace the first `- [ ]` with `- [x]` (or otherwise denote completion, like strikethrough text). This assumes tasks are being done in the listed order, which is usually the case unless Claude tackles them out of order. (Claude Code typically works through the plan sequentially unless directed otherwise.)
* **Optional:** If needed, the script could use context to ensure it’s marking the correct task. For instance, it might compare the file or command just executed with the task descriptions. E.g., if `$CLAUDE_TOOL_NAME` is `Bash` and the command was `npm test`, the script could match that to a task containing “Run tests” to be sure it’s marking the right item. However, a simpler approach is to assume tasks are done in order and always mark the next pending task.
* **Save `plan.md`:** The file now reflects progress. For example:
  `- [x] Create dark mode toggle component in settings page` (completed)
  `- [ ] Add state management for dark mode` (next pending)
  `- [ ] Run tests to verify functionality` (pending)

Claude may also be tracking these internally via its Todo list (using the TodoWrite/TodoRead tools), but those internal updates are not visible to the user. Our hook ensures the user has a real-time view of progress in `plan.md`.

This hook will run after every relevant tool usage. If Claude executes multiple file edits or commands for one task, each PostToolUse will trigger. We should be careful not to prematurely mark multiple tasks. A conservative strategy is to only mark one task per hook call (the topmost unchecked item). This way, even if a single complex task involved two edits, we wouldn’t mark two tasks at once. The plan.md will only tick off the next task when appropriate.

**Edge cases:** If Claude performs a non-plan action (e.g., reads a file or searches in between), our matcher filters will skip those (since we match only Edit/Write/MultiEdit/Bash). We won’t mark a task until a modifying action is done. This aligns with the idea that a task is “complete” when the intended code change or effect is achieved.

## Archiving the Plan on Completion

Once all tasks are completed, we want to archive the plan for future reference. This involves renaming `plan.md` and moving it to an archive directory with a timestamp and description.

**Trigger:** When the entire plan is finished. The final step likely involves Claude signaling it is done (often printing a completion message or simply stopping). We use the **Stop** hook event, which fires when Claude’s main agent has finished responding. In other words, when the AI stops on its own (not interrupted) at the end of the session or task, the Stop hook runs.

**Hook Setup:** Add a Stop event hook in settings:

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        { "type": "command", "command": "./scripts/plan_hook.sh finalize" }
      ]
    }
  ]
}
```

(No matcher is needed for Stop, since it’s a single event for the session’s end.)

**Action:** The `finalize` part of our script will:

* **Check completion:** It may verify that all tasks are indeed marked done. (For example, open `plan.md` and ensure no `- [ ]` remains, or that all tasks are checked off.) This double-check prevents archiving too early (e.g., if a Stop hook triggered on an intermediate stop – although normally Stop runs at the end of the assistant’s output, we should be sure it’s the final completion, not the end of the plan presentation.) If tasks remain, the script can choose not to archive yet.
* **Create archive folder:** Ensure the `archiveFolder` exists (create it if not).
* **Generate filename:** Use the specified `archiveFilenamePattern` to form a name. For example, if the pattern is `<timestamp>-<description>.md`, the script will get the current date-time (e.g. `2025-07-12_09-18-30`) and extract the project description from the plan content's title/heading. For example: `2025-07-12-add-dark-mode-plan.md`.
* **Rename/Move file:** Rename `plan.md` to the new filename and move it into `archiveFolder`. This could be as simple as a shell `mv plan.md archives/2025-07-12-add-dark-mode.md`. After this, the current `plan.md` is gone (moved), which signals that the active plan is completed. Future runs will create a new plan.md for new tasks.
* (Optional) **Logging:** We might log this archive action or maintain an index (maybe append a line to an archive log file with the timestamp and description). This wasn’t explicitly requested, but could be useful for record-keeping.

After archiving, the working directory will no longer have an active `plan.md` (until a new plan is made in a subsequent session). Old plans are safely stored in the archive with context of when and what they were for.

## Configuration and Setup in Claude CLI

To implement these hooks, we need to configure Claude Code’s hook system. Claude Code allows hooks via its settings files or the interactive `/hooks` command.

**Registering Hooks:** We will add entries to the project’s `.claude/settings.json` (or `.claude/settings.local.json` if we don’t want it in version control). The structure follows the format (in JSON) shown in Anthropic’s docs:

```json
{
  "hooks": {
    "PreToolUse": [ ... ],
    "PostToolUse": [ ... ],
    "Stop": [ ... ]
  }
}
```

Within each event, we specify matchers (if needed) and the commands to run. The CLI merges these with any global hooks in `~/.claude/settings.json`. Ensure the commands or scripts we reference are accessible and have execute permission (e.g. run `chmod +x plan_hook.sh`).

Alternatively, we could configure hooks via the CLI UI: using the `/hooks` slash command to interactively add a hook for each event and typing the shell command. Under the hood, this updates the settings JSON. Using the config file directly is convenient for complex commands.

**Local vs Global:** Since this plan management is likely specific to our projects (and uses project-specific paths like a template path or archive folder), we’ll configure it at the project level. (Global hooks are possible if we want this behavior for all projects by default, but then paths may need to be generalized.)

**Hook Script Implementation:** We can implement `plan_hook.sh` (or it could be a Python/Node script). This script will probably need to handle different subcommands (init/update/finalize). We can differentiate by an argument we pass (as shown in the commands above) or by checking `$CLAUDE_EVENT_TYPE`. For example, the script could examine the env var and call the appropriate function for PreToolUse vs PostToolUse vs Stop. Using one unified script has the advantage of sharing state or functions between phases (for instance, keeping the template loaded in memory – though each hook call is a separate process invocation). On the other hand, separate scripts for each phase could be simpler. The design choice is open, but ensure each script quickly exits to not hold up Claude’s operation (hooks should be fast, or consider running long processes in background threads).

**Modes and Permissions:** We assume Plan Mode is used to generate the plan, and once exited, Claude might continue either in a normal step-by-step mode or in an “auto-accept” mode. If manual permission prompts for each tool are still enabled, our PreToolUse hook will run after each approval. If auto-accept mode is turned on upon plan approval (as sometimes configured), Claude will execute tools without pausing, but the hooks still trigger as normal. In either case, the hooks function the same – they don’t require any special permission. (Hooks run automatically with your user privileges, so be mindful that the scripts are trusted.)

**Settings to verify:** In the template and script, ensure the paths (like `templatePath`, `archiveFolder`) are correct. These could be hard-coded in the script or passed via environment variables. For example, one might set environment variables in the `.claude/settings.json` for the template path or description and reference them in the hook command (e.g., `command": "TEMPLATE_PATH=docs/plan_template.md DESCRIPTION='add-dark-mode' ./plan_hook.sh init"`). Claude Code doesn’t have a built-in concept of “user-provided description” for a session, so this is something we supply via config or as part of running the CLI (perhaps as an environment variable or argument).

Finally, test the setup: Run a sample plan in Claude Code (in a safe environment) and ensure that after accepting the plan, `plan.md` appears with the correct content, tasks get checked off as Claude works, and at the end the file is moved to archives with the expected name. Adjust any file paths or patterns as needed.

## Implementation Decisions

Based on analysis, the following implementation choices have been made:

* **Project Naming:** Extract project description automatically from LLM plan content
* **Task Completion:** Use simple sequential detection - mark first uncompleted task when tools execute
* **Archive Structure:** Extract title from plan content for meaningful archive filenames
* **Task Format:** Use checkboxes `[ ]`/`[x]` for individual tasks, emojis (⏳🚧✅) for section headings
* **Error Handling:** Apply best judgment with graceful degradation and sensible defaults

## Summary of What's Needed

* **Claude Code Hooks:** Utilize `PreToolUse`, `PostToolUse`, and `Stop` events to inject our automation at the right moments. This gives us deterministic control over creating, updating, and finalizing the plan file.
* **Template File:** A Markdown template with predefined structure for the plan. The hook will fill in the dynamic TODO list using this template.
* **Script/Commands:** Custom shell commands or scripts that handle:

  * Reading the template and writing `plan.md` with the tasks (on plan acceptance).
  * Marking tasks as done in `plan.md` (after each tool action).
  * Archiving the `plan.md` (after completion).
* **Project Settings Config:** Define the hooks in `.claude/settings.json` (or via `/hooks`). Make sure to include any necessary matcher patterns and that the commands point to the correct script location. For example, use regex matchers for multiple tools or list multiple hook entries as needed.
* **Environment & Paths:** Plan out how the script knows `templatePath`, `archiveFolder`, and the archive naming. These can be hard-coded in the script or passed as env vars in the hook command. Also ensure the archive directory exists or is created by the script.
* **Error Handling:** Apply best judgment for graceful degradation - handle missing files, parsing errors, and edge cases with sensible defaults.

By gathering all this information and setting up the hooks accordingly, we’ll have a robust automation: as soon as you approve Claude’s plan, the `plan.md` appears (populated with the tasks from Claude’s plan), it stays up-to-date as Claude works through each step, and when done, it’s neatly archived with a timestamp and description for future reference. This spares us from having to manually track the plan and gives persistent documentation of what was implemented.

**Sources:**

* Anthropic Claude Code Hooks Documentation – details on hook events and configuration.
* Reddit discussion on Plan Mode – confirms that Claude awaits user approval of a plan before executing.
* *ClaudeLog* examples – illustrate how Claude presents a plan as a list of tasks in Plan Mode.
