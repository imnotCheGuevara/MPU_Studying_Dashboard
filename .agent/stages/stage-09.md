# Stage 09 — Integration hardening, privacy, and diagnostics

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-08.md

## Prerequisite gate

Stages 06, 07, and 08 must be accepted and Stage 09 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 09 only: Phase 1 integration hardening, privacy controls, and diagnostics for Campus Dashboard.

Follow the context-efficiency rules without weakening acceptance: use medium reasoning by default when selectable; do the bootstrap read once for this task; use narrow source reads and focused tests while developing; keep verbose successful build/test output in temporary logs; surface complete relevant failure details; and run the full required suite plus Stage 09 checks before handoff. Do not repeat unchanged bootstrap reads merely because the user says `continue`. Repeat the full suite only for a flaky regression or an explicit acceptance requirement.

Exercise and harden the complete application. Add end-to-end scenarios with fake services, permission-denial/revocation recovery, source status and actionable error presentation, categorized local-data clearing, separate credential clearing, calendar-event cleanup preview, redacted diagnostic export, accessibility/basic keyboard behavior, and performance/responsiveness checks. Fix integration defects within Phase 1 scope and add regression tests. Do not redesign global requirements or add Phase 2 features.

Acceptance:
- End-to-end tests cover first sync, incremental updates, one-source failure, offline recovery, cancellation, calendar/notification outbox retry, AI confirmation, app restart, and permission revocation.
- Secret scanning and diagnostic-export tests find no credential/session leakage.
- Clearing one data category does not unexpectedly clear credentials or calendar events.
- Calendar cleanup is separate, previewable, and limited to valid app-owned bindings.
- The UI remains usable with Canvas, SIweb, Calendar, Notifications, AI, or background service independently unavailable.
- Build, unit, integration, and applicable UI tests all pass from documented commands.

Write .agent/handoffs/stage-09.md and include unresolved risks for real-device testing. Do not claim iCloud or seven-day acceptance.
