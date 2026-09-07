# Stage 06 — Apple Calendar integration

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-05.md

## Prerequisite gate

Stage 05 must be accepted and Stage 06 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 06 only: Apple Calendar/EventKit integration for Campus Dashboard.

Implement EventKit permission handling, dedicated-calendar creation/selection, iCloud-versus-local source status, persistent calendar/source identity, safe recovery when identifiers change, per-event CalendarBinding, and durable outbox consumption for create/update/delete. Only eligible course meetings and official or user-confirmed deadlines may be written. Never identify an event by title alone and never touch an event without a valid app-owned binding. Permission denial or missing calendar must not break the rest of the app.

Acceptance:
- Adapter/domain tests use fakes to cover permission denied/revoked, duplicate calendar names, local versus iCloud source, lost calendar identifier, unwritable calendar, event create/update/cancel, retry, and stale binding.
- Replaying outbox work creates no duplicate event.
- Unconfirmed inferred dates are rejected at the calendar boundary.
- A manual Mac test in a dedicated non-production test calendar verifies create, update, cancel, and repeated sync without touching unrelated events. iPhone verification belongs to Stage 10.

Write .agent/handoffs/stage-06.md. Do not implement notification scheduling, AI parsing, or the seven-day trial.
