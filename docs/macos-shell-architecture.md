# macOS Shell Architecture

## Status

This document defines the first product-layer design on top of the existing `apple-mcp` foundation.

What already exists in this repo:

- Apple app MCP servers for Notes, Messages, Contacts, Reminders, Calendar, Maps, Mail, and Music
- `knowledge-corpus` as the canonical operating brain query layer
- `mail-intelligence` as the live Apple Mail sensor and Daily Intel generator
- Repo memory files that describe the three-persona inbox model

What does not exist yet:

- A native SwiftUI macOS shell
- A computer-use layer for general UI control
- Final Cut Pro or Motion automation beyond basic app visibility and manual investigation

## Product Goal

Build a native macOS control surface that combines:

- A SwiftUI shell for daily operating context
- MCP-backed access to Apple apps and the canonical brain
- A swappable computer-use layer for apps that do not expose adequate automation APIs
- Production workflows for media assembly, monitoring, and guided creative operations

## Design Principles

- Keep the current MCP foundation independently usable and shippable.
- Treat the shell as a separate product layer, not a rewrite of the servers.
- Put hard seams around computer-use so it can be replaced later.
- Keep user data local by default.
- Design for a personal-first release path without blocking a later commercial version.

## Architecture

### 1. SwiftUI Shell

The shell is the native macOS application and primary user surface.

Primary views:

- `Cockpit`: inbox intelligence, calendar, reminders, current media, and active jobs
- `Agent Terminal`: natural-language command bar and routed task execution
- `Production Dashboard`: FCP/Motion-oriented jobs, export state, and workflow tracking

Shell responsibilities:

- session state
- navigation
- permission onboarding
- model/provider selection
- rendering structured outputs from MCP tools
- showing computer-use task progress, screenshots, and approvals

### 2. Agent Router

The router receives typed intents from the shell and decides which control plane should execute them.

Examples:

- "Scan today’s three inboxes" -> `mail-intelligence`
- "Show the operator persona rules" -> `knowledge-corpus`
- "Pause the current playlist" -> `apple-music`
- "Export the current FCP timeline" -> computer-use provider

The router should prefer deterministic MCP tools first and only fall back to computer use when no good API exists.

### 3. MCP Daemon Layer

The current repo already provides this layer.

Initial server set:

- `apple-notes`
- `apple-messages`
- `apple-contacts`
- `apple-reminders`
- `apple-calendar`
- `apple-maps`
- `apple-mail`
- `apple-music`
- `mail-intelligence`
- `knowledge-corpus`

Product requirement:

- The shell should launch and supervise these as local child processes instead of requiring users to wire them manually in editor configs.

### 4. Computer-Use Layer

This layer is required for apps like Final Cut Pro and Motion where direct automation is limited or absent.

Define a provider seam:

```ts
export interface ComputerUseProvider {
  name: string;
  startSession(): Promise<string>;
  captureState(sessionId: string): Promise<ComputerUseState>;
  execute(sessionId: string, action: ComputerUseAction): Promise<ComputerUseResult>;
  stopSession(sessionId: string): Promise<void>;
}
```

Planned provider implementations:

- `CuaComputerUseProvider`
  Uses screen capture plus simulated input for a personal/direct-distribution build.
- `AccessibilityComputerUseProvider`
  Uses macOS accessibility primitives where feasible for a more platform-native future path.

Rules:

- The shell must depend on the interface, not a concrete provider.
- Computer-use actions must be logged as structured events.
- Long-running media tasks must support resume/retry state.

### 5. Canonical Brain and User Data

The canonical brain remains the source of truth for structured operating context.

Current source:

- `knowledge-corpus/data/mojosolo_operating_brain.json`

Product direction:

- user-scoped local brain file
- system keychain for secrets and account material
- Notes remain an output sink, not a source of truth
- event logs and job history stored separately from the brain

## FCP and Motion Reality

Current conclusion:

- Final Cut Pro does not currently give this repo a practical editing/export automation surface through the existing MCP stack.
- Motion does not currently have a usable automation surface in this repo.

That means:

- assembly automation
- creative-direction loops
- export monitoring inside those apps

must initially rely on the computer-use layer.

The shell should treat FCP and Motion as `computer-use-first` applications until a better native strategy is proven.

## Initial Modules

### Shell App

- SwiftUI app target
- view models for cockpit, terminal, and production dashboard
- permission and onboarding flow
- child-process manager for MCP daemons

### Router Core

- intent schema
- tool registry
- deterministic routing rules
- fallback rules to computer use

### Provider Runtime

- provider interface
- session lifecycle manager
- screenshot/action log model
- error handling and cancellation

### Job System

- media job definitions
- progress state
- retry and resume
- notification hooks

## Release Strategy

### Phase 1

Personal-first product build:

- SwiftUI shell
- local MCP daemon management
- current brain integration
- initial computer-use provider
- direct distribution outside the App Store

### Phase 2

Stabilization and repeatable workflows:

- assembly templates
- job queue
- media workflow presets
- richer telemetry and recovery

### Phase 3

Commercial hardening:

- per-user onboarding
- secrets and account isolation
- pluggable provider strategy
- clearer boundary between personal brain defaults and distributable product defaults

## Immediate Build Plan

1. Create the SwiftUI app scaffold in a new product directory.
2. Add a local daemon manager for the 10 existing MCP servers.
3. Define the router intent model and map the first shell actions to existing MCP tools.
4. Create the computer-use provider protocol and a stub implementation.
5. Add the three core views: cockpit, agent terminal, and production dashboard.
6. Add structured job logging for media tasks.

## Open Questions

- Which model/runtime will drive the shell’s agent router by default?
- Should the first computer-use provider be embedded or launched as an external helper?
- What is the minimum viable FCP workflow for the first demo: assembly, creative direction, monitoring, or all three?
- How much of the current MojoSolo brain should remain repo-bundled versus moved to user-local state at first launch?
