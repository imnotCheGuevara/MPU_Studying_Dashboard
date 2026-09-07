# Stage 07 — Notifications and background scheduling

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-05.md

## Prerequisite gate

Stage 05 must be accepted and Stage 07 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 07 only: local notifications and macOS background scheduling for Campus Dashboard.

Implement UserNotifications permission/state handling, deterministic notification identifiers, deadline/class reminders, new-item notifications after baseline, course-level settings, quiet hours, cancellation/rescheduling, repeated-failure suppression, and recovery notifications. Implement the documented hourly target scheduling and post-sleep/offline compensating sync using a user-visible, user-controllable macOS background mechanism. The app must work when permissions or the background item are disabled.

Acceptance:
- Tests cover permission states, unique keys, repeated sync, due-time changes, cancellation, quiet-hour delay/drop rules, expired reminders, first-sync baseline, failure suppression/recovery, and timezone/DST edges.
- Replaying notification outbox work does not duplicate scheduled notifications.
- Unconfirmed inferred dates cannot schedule deadline notifications.
- Manual checks verify enable/disable behavior and a short-interval development-mode schedule without claiming execution while the Mac is asleep/off.

Write .agent/handoffs/stage-07.md. Do not implement AI parsing or real-device iCloud acceptance.
