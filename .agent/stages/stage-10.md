# Stage 10 — Real-device acceptance and seven-day trial

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-10.md when resuming; Stage 15 acceptance and frozen release-candidate identity must be present in CURRENT.md.

## Prerequisite gate

For the current resume path, Stages 10R and 15 must be accepted and the main conversation must explicitly set Stage 10 to READY or IN PROGRESS at 0/7. Confirm the exact state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 10 only: final real-device acceptance and the seven-day operational trial for Campus Dashboard. The trial resumes at 0/7 against the signed release candidate frozen and accepted in Stage 15. Mailbox integration is outside the product and acceptance scope.

Follow the execution discipline summarized in `AGENTS.md`. Use medium reasoning by default when selectable, keep successful logs concise, avoid rereading unchanged bootstrap files on plain continuation turns, and preserve complete evidence for every real-device and seven-day acceptance result. Read a targeted section of `.agent/EXECUTION_RULES.md` only if a concrete procedural gap arises.

Guide and record acceptance on the user's real Mac, Canvas account, authorized SIweb pages, DeepSeek account, dedicated iCloud Campus Dashboard calendar, and iPhone. Never ask for credentials in chat or include private school content in the handoff. Verify the Stage 15 frozen build identity, then revalidate all acceptance-affecting setup/device checks. Preserve privacy-safe historical evidence only where this build cannot affect it, but keep the counter at 0/7 and start Day 1 on the next complete Asia/Macau calendar day after setup revalidation; no earlier partial day counts. Verify initial/incremental/repeated source sync, DeepSeek consent/classification/failure, source update/cancellation, offline/sleep recovery, permission denial/recovery, notification timing, and iCloud create/update/delete behavior. Run the seven-day trial, triage defects, implement only necessary approved-scope fixes with regression tests, rebuild/refreeze and restart affected evidence when required, and continue until mandatory acceptance passes or an external blocker is explicit.

Acceptance:
- Mac and iPhone show exactly one event for a test create; the same event updates and then disappears on authorized cancellation.
- Repeated sync creates no duplicate events or notifications and no unrelated calendar item changes.
- No unconfirmed AI-derived date enters Calendar or deadline notifications.
- Source failures are isolated and explainable; recovery catches up safely.
- DeepSeek remains opt-in, sends only approved Canvas announcement fields, and respects budgets/cache.
- The built product contains no mailbox authorization or mail-network path.
- Seven consecutive trial days have a dated, privacy-safe log.
- All discovered critical/high-severity Phase 1 defects are fixed and regression-tested.

Write .agent/handoffs/stage-10.md. Mark PASS only after the full seven-day evidence exists. Do not begin Phase 2 AI study coaching.
