# Stage 05 — Sync engine and deterministic normalization

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-04.md; Stage 03 acceptance is summarized in CURRENT.md.

## Prerequisite gate

Stages 03 and 04 must be accepted and Stage 05 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 05 only: synchronization orchestration and deterministic normalization for Campus Dashboard.

Integrate the two connectors through a source-independent sync engine. Implement per-source runs, full/incremental semantics where supported, deterministic mapping into the unified model, transactional change application, change records, durable calendar/notification outbox entries, idempotency, single-flight per source, cancellation, error isolation, first-sync baseline behavior, retry classification, and the specified deletion-evidence rules. Calendar and notification adapters remain fakes in this stage.

Acceptance:
- Tests prove one source failure does not block or corrupt the other.
- Repeated sync is idempotent and produces no duplicate domain records or outbox work.
- Title/time/location/status updates modify the same object and generate correct changes.
- Incomplete pagination, failed requests, or one missing item never cause deletion.
- Explicit cancellation and two successful complete-snapshot absences follow the specified soft-delete behavior.
- Database commit and outbox crash-recovery tests pass.
- First sync does not create a notification storm for historical records.
- Baseline completion must be tracked conservatively for each source/object family: an incomplete initial snapshot must not make a later first complete snapshot's historical tasks or announcements appear as newly published. Add a restart-durable regression test covering incomplete first read followed by a complete historical snapshot.
- Every valid connector payload must remain idempotent, including an announcement whose source omits both publication and update timestamps. A local fallback timestamp must remain stable across unchanged syncs and must not create repeated ChangeRecords, updated counts, or outbox work.

Write .agent/handoffs/stage-05.md with exact test evidence. Do not implement real EventKit, notifications, background scheduling, or AI.
