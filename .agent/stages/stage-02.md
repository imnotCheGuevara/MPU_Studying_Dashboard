# Stage 02 — Persistence, Keychain, and service contracts

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-01.md

## Prerequisite gate

Stage 01 must be accepted and Stage 02 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 02 only: persistence, Keychain, and external-service contracts for Campus Dashboard.

Implement the local persistence and security foundation without connecting to live services. First promote the Stage 01 SwiftPM executable into a reproducibly packaged macOS `.app` with a stable bundle identifier, Info.plist, and a documented signing/entitlement strategy suitable for later Keychain, EventKit, UserNotifications, App Sandbox, and Service Management work. Full Xcode is not currently installed, so a deterministic packaging script is acceptable if it produces and launches a valid `.app`; document what will still require Xcode or a stable development signature. Add schema/migrations for source accounts, raw source records, courses, meetings, learning tasks, announcements, local user state, sync runs, change records, calendar bindings, notification deliveries, AI parse results, and durable outbox work. Preserve official, local, and inferred fields separately. Add a Keychain abstraction and fake implementation for tests. Define testable protocols/interfaces for Canvas, SIweb, sync, calendar, notifications, AI, clock, and ID generation. Wire the existing fake-data app through repositories where reasonable.

Required deliverables:
- Reproducible `.app` packaging with stable bundle identity, Info.plist, and documented signing/entitlement baseline.
- Versioned database schema and migration strategy.
- Repository operations with composite source uniqueness and restart persistence.
- Keychain-backed secret store; no secret values in the database or logs.
- Mock/fake service implementations for later stages.
- Tests for migrations, CRUD, uniqueness, local/source-state separation, outbox persistence, and Keychain error handling.
- Updated architecture/data-model documentation.

Acceptance:
- Build and all tests pass.
- The packaged `.app` launches through macOS as an application and reports the documented bundle identifier; Keychain integration is exercised from that packaged identity.
- A restart/integration test proves persisted history survives process recreation.
- Duplicate source objects upsert rather than duplicate.
- A repository-wide check finds no embedded example credential.
- Denied/unavailable Keychain states fail safely and are visible to the caller.

Write .agent/handoffs/stage-02.md. Mark PASS only with command evidence. Do not implement live Canvas/SIweb, EventKit, notifications, background services, or AI.
