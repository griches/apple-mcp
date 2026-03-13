# macOS Operator Roadmap

**Branch:** `feat/macos-shell`  
**Date:** March 12, 2026  
**Goal:** Turn the current `apple-mcp` + `shell/` foundation into a usable personal macOS operator layer that gives you practical control over your Mac and Apple-native apps by the next morning, then extends that into a durable control plane over the next 30 tasks.

## Reality Check

"Full control" on macOS does **not** mean bypassing SIP, TCC, or private OS protections. The realistic target is:

- deterministic control of supported Apple apps through MCP and Apple automation
- operator-level control of unsupported apps through Accessibility + screen-based computer use
- a native shell that can supervise daemons, execute workflows, persist job history, and surface failures clearly
- explicit user-granted permissions for Accessibility, Screen Recording, Apple Events, Full Disk Access, and any app-specific automation you choose to allow

That is enough to get very close to "I can run my Mac from one control surface" without pretending the platform is less opinionated than it is.

## Current State

Already working on this branch:

- SwiftUI shell with `Cockpit`, `Agent Terminal`, and `Production Dashboard`
- 10 MCP-backed Apple/native data servers
- deterministic router with Claude primary and OpenAI fallback
- native `CuaComputerUseProvider` for local screen/input automation
- FCP share/export discovery and verified workflow titles
- readiness onboarding layer
- `swift build` passing
- `swift test` passing with `64/64` green

Still missing for true operator use:

- persistent production jobs and event history
- runtime daemon health and restart controls
- app coverage beyond the existing Apple app MCP set
- true action surfaces for Finder, Safari, System Settings, and Shortcuts
- persistent automation artifacts and audit trail
- a coherent "one place to operate the Mac" experience

## Success Definition For Morning

By morning, you should have:

- a shell that launches cleanly and tells you exactly what is unavailable
- persistent production jobs instead of mock rows
- daemon health visible in the UI, with restart actions
- one place to run Apple-app data workflows and one place to run computer-use workflows
- first-party control over the most important native app surfaces: Mail, Messages, Notes, Calendar, Reminders, Contacts, Maps, Music, Finder, Safari, Shortcuts, System Settings, Final Cut Pro

## App Coverage Roadmap

**Already integrated via MCP**

- Notes
- Messages
- Contacts
- Reminders
- Calendar
- Maps
- Mail
- Music
- knowledge-corpus
- mail-intelligence

**High-priority app control to add next**

- Finder
- Safari
- System Settings
- Shortcuts
- Notification Center / user notifications
- Final Cut Pro runtime operations
- Motion runtime operations

**Second-wave app control**

- Preview
- Photos
- QuickTime Player
- Terminal / iTerm
- Filesystem / export destinations

## Workstreams

1. **Operator Shell**
   `Cockpit`, `Agent Terminal`, `Production Dashboard`, shared status surfaces, app navigation.
2. **Native App Control**
   MCP servers, AppleScript / Apple Events / Shortcuts / Finder / Safari / System Settings integration.
3. **Computer Use**
   Accessibility + screen-based execution, screenshot persistence, approvals, helper-process hardening.
4. **Production Jobs**
   Persistent jobs, event logs, resumability, render/export monitoring.
5. **Runtime Health**
   Daemon lifecycle, restartability, diagnostics, permissions, onboarding, auditability.

## Prioritization

### Must Have Tonight

- persistent job store
- daemon health UI
- restart actions for failed daemons
- Finder and Safari control surfaces
- Shortcuts bridge for native workflow fan-out
- screenshot and event persistence for computer-use runs

### Should Have Next

- System Settings deep actions
- richer Production Dashboard state
- notification delivery for completed/failed jobs
- approval checkpoints for risky computer-use steps
- export destination/file handling

### Could Have Later

- Motion-specific workflow pack
- Preview / Photos / QuickTime support
- menu-bar quick actions
- LaunchAgent / background auto-start
- XPC helper split for computer use

## 30-Task Roadmap

### Phase 1: By Morning

**Task 1. Persist production jobs**
- Create `JobStore` under `Application Support/MojoShell/jobs.json`.
- Move sample rows out of `ProductionDashboardView`.
- Outcome: dashboard reflects real stored jobs, not mock data.

**Task 2. Persist production event history**
- Add `JobEvent` and append-only event log.
- Record queued, started, step progress, completed, failed, canceled.
- Outcome: every run has a durable execution trail.

**Task 3. Introduce `ProductionController`**
- Centralize job execution orchestration outside the view.
- Move workflow mutation logic out of `ProductionDashboardView`.
- Outcome: view becomes a renderer, not the workflow engine.

**Task 4. Persist computer-use screenshots**
- Save screenshot files from `ComputerUseResult.screenshotAfter`.
- Store paths in job events instead of only keeping `Data?` in memory.
- Outcome: failures and approvals are inspectable after the run ends.

**Task 5. Add daemon runtime health model**
- Extend runtime state beyond artifact presence.
- Track `notBuilt`, `stopped`, `starting`, `running`, `failed`.
- Outcome: shell can tell the difference between "built" and "alive."

**Task 6. Add daemon diagnostics panel**
- New shell panel or section listing all 10 daemons with status and last error.
- Outcome: you can see what is actually operational without reading logs.

**Task 7. Add per-daemon restart actions**
- Restart one daemon or all daemons from the shell.
- Outcome: no terminal round-trip needed when a daemon dies.

**Task 8. Add Finder control surface**
- Create a Finder MCP/control seam for:
  - reveal path
  - open folder
  - list current selection
  - move/copy/export target prep
- Outcome: shell can direct file destinations and inspect export targets.

**Task 9. Add Safari control surface**
- Create a Safari MCP/control seam for:
  - open URL
  - get current tab URL/title
  - run link-opening workflows from shell
- Outcome: shell can drive web destinations and operator research flows.

**Task 10. Add Shortcuts bridge**
- Add a Shortcuts runner for named shortcuts with typed inputs.
- Outcome: you get immediate leverage across macOS-native automations without writing custom bridges for everything.

### Phase 2: Morning Stabilization

**Task 11. Add System Settings deep-link actions**
- Shell actions for opening Accessibility, Screen Recording, Full Disk Access, Automation panes.
- Outcome: readiness issues become one-click recoverable.

**Task 12. Add Apple Events readiness**
- Extend readiness to cover automation permission state where feasible.
- Outcome: app-control failures are surfaced before runtime.

**Task 13. Add action approvals**
- Introduce confirmation checkpoints for destructive or high-risk computer-use steps.
- Outcome: "full control" remains operator-safe.

**Task 14. Add notification delivery**
- Fire local notifications for job completion, failure, and daemon failure.
- Outcome: you do not need to stare at the shell to know when work finishes.

**Task 15. Add export target management**
- Integrate Finder-aware export destination selection.
- Outcome: FCP workflows can finish into known folders, not ambiguous defaults.

**Task 16. Add FCP workflow presets**
- Formalize named workflows: export current timeline, export project, monitor background tasks.
- Outcome: dashboard actions become repeatable presets instead of one-off steps.

**Task 17. Add Motion workflow placeholders**
- Mirror the FCP model with Motion-specific discovery, activation, and task logging.
- Outcome: Motion becomes a first-class target instead of a note in the design doc.

**Task 18. Add command palette**
- Global shell action runner for app actions, workflow starts, daemon restarts, and shortcut execution.
- Outcome: faster operator loop than navigating views.

**Task 19. Add operator audit view**
- Timeline of actions across MCP calls, computer-use steps, daemon restarts, and job events.
- Outcome: you can answer "what happened on this Mac?" from one screen.

**Task 20. Add recovery and retry flows**
- Retry failed jobs from stored state.
- Outcome: failures are resumable, not dead ends.

### Phase 3: Native macOS Control Expansion

**Task 21. Create Finder-native MCP server or bridge**
- Promote Finder control from ad hoc shell logic into a reusable server/tool layer.
- Outcome: file control becomes durable and scriptable across the stack.

**Task 22. Create Safari-native MCP server or bridge**
- Promote Safari control into a reusable tool layer.
- Outcome: browser workflows become part of the operator runtime, not UI glue.

**Task 23. Add System Events / AppleScript adapter**
- Wrap AppleScript / System Events into a narrow, typed adapter instead of sprinkling direct calls everywhere.
- Outcome: native app automation expands cleanly.

**Task 24. Add Shortcuts result parsing**
- Capture structured outputs from shortcuts.
- Outcome: shortcuts become true tools, not fire-and-forget buttons.

**Task 25. Add Preview / document operations**
- Open, inspect, and route exported deliverables.
- Outcome: QA loop for exports stays in the shell.

**Task 26. Add Photos / asset intake hooks**
- Pull user-selected media into assembly workflows.
- Outcome: operator shell becomes the intake point for local media.

### Phase 4: Production Hardening

**Task 27. Split computer-use helper from app process**
- Move toward the planned helper/XPC seam.
- Outcome: crashes or permission issues in computer use do not destabilize the shell.

**Task 28. Add richer job schema**
- Include client, template, source assets, output path, screenshots, error context, and workflow version.
- Outcome: jobs are auditable and compatible with future template systems.

**Task 29. Add launch/recovery behavior**
- Auto-restore previous jobs, daemon state, and open context on relaunch.
- Outcome: the shell feels like an operator console, not a demo app.

**Task 30. Add morning-ops mode**
- One consolidated launch mode showing:
  - readiness summary
  - daemon status
  - inbox scan
  - calendar/reminders
  - active production jobs
  - one-click app/workflow controls
- Outcome: you can realistically start your day from MojoShell alone.

## Recommended Execution Order

If the target is "usable by morning," do these first:

1. Task 1 — `JobStore`
2. Task 2 — `JobEvent` log
3. Task 3 — `ProductionController`
4. Task 5 — daemon runtime health
5. Task 6 — daemon diagnostics UI
6. Task 7 — restart actions
7. Task 8 — Finder control
8. Task 9 — Safari control
9. Task 10 — Shortcuts bridge
10. Task 14 — local notifications

That gives you a believable overnight operator shell instead of more internal cleanup.

## Suggested Morning Deliverable

If you want a single demo state by morning, the shell should support this sequence:

1. Open MojoShell.
2. Read readiness and daemon health.
3. Scan inboxes and today’s context.
4. Open Finder export folder.
5. Launch a Shortcut that prepares a workflow context.
6. Run an FCP export workflow.
7. Persist screenshots, events, and output paths.
8. Receive a completion notification.
9. Open the export in Finder or Preview.
10. Return to the shell to review the audit log.

## What Not To Do Tonight

- don’t chase App Store packaging
- don’t over-engineer XPC before job persistence exists
- don’t add more mock UI
- don’t attempt "all apps" at once
- don’t treat artifact presence as daemon health
- don’t promise unsafe or hidden-API control over macOS internals

## Definition Of Done For This Roadmap Slice

This roadmap succeeds if, by the next checkpoint, MojoShell becomes:

- the place where you see what your Mac can currently do
- the place where you recover broken automation
- the place where you launch native app workflows
- the place where you inspect what happened afterward

That is the shortest honest path to "full control over my macOS and native applications" from the current branch state.
