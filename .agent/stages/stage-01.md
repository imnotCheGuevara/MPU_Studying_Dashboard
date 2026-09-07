# Stage 01 — App foundation and fake-data UI

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: None for a first implementation; if resuming, read only .agent/handoffs/stage-01.md.

## Prerequisite gate

The main conversation must authorize Stage 01. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 01 only: app foundation and fake-data UI for Campus Dashboard.

Build a native macOS Swift/SwiftUI project foundation. Define the initial domain-facing types needed by the UI and create completely synthetic sample data. Implement usable navigation and the primary screens: Today, Schedule, Tasks, Announcements, AI Confirmation Queue, and Settings. Show source health, last-sync states, loading/empty/error/permission-denied states, and manual-refresh affordances. No real connectors, credentials, EventKit writes, notifications, or external AI in this stage.

Required deliverables:
- A reproducibly buildable macOS project with a documented minimum macOS version.
- Clear feature/module boundaries that later stages can extend.
- Synthetic fixtures containing no real student data.
- UI for every required primary page and important state.
- Unit/UI or view-model tests appropriate to the chosen project structure.
- README build/test instructions.

Acceptance:
- Clean build succeeds with the documented command.
- Automated tests pass.
- App launches and all primary pages are navigable using fake data.
- Empty, loading, error, and denied states can be intentionally previewed or selected.
- No secret, live network call, calendar write, notification request, or AI call exists.

Write .agent/handoffs/stage-01.md using the mandated template. Mark PASS only if every acceptance item was actually checked. Do not begin Stage 02 or edit central planning/constraint files.
