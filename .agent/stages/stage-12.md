# Stage 12 — Canvas announcement academic-signal classification

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-11.md

## Prerequisite gate

Stage 11 must be accepted and Stage 12 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 12 only: DeepSeek-backed classification of already-synchronized Canvas announcements into actionable local academic signals.

Implement deterministic-first Canvas announcement analysis using the Stage 11 provider. The fixed primary taxonomy is `course_schedule_change`, `assignment_deadline`, `exam_time`, or `other`; one announcement may produce zero or more signals. Each non-other signal stores source-announcement identity, shortest useful evidence excerpt, key requirement, inferred date/time if any, confidence, reason, conflicts, provider/model/prompt/schema provenance, and confirmation state. Preserve the source announcement and original language unchanged.

Build the minimum outbound payload from title, bounded sanitized body excerpt, minimum course context, locale, and schema instructions only. Strip hidden HTML, scripts, remote media, trackers, Canvas/source URLs, author email, user identity, tokens, cookies, attachment text, and unrelated history. Treat all announcement text as untrusted data, never instructions. Official Canvas fields and dates remain authoritative. Every date extracted from announcement text is inferred regardless of confidence and must enter the existing confirmation queue before any Calendar or deadline-notification eligibility.

Add local UI for classification status, category filtering, evidence/reason/conflict inspection, reprocess, disable, correct/reject/confirm, and original-source navigation. Do not pretend AI labels are Canvas facts. Use red for official assignment/quiz deadline events in the app's own Schedule presentation while retaining an explicit deadline symbol/text so color is not the sole cue; this does not change the Apple Calendar per-calendar color model.

Allowed scope: Canvas announcement read models, AI orchestration and persistence for AcademicSignal, confirmation workflow, Announcements/Schedule/Settings localization and presentation, additive migrations, focused tests, and .agent/handoffs/stage-12.md. Do not change the Canvas connector's read-only contract, Outlook, Apple Calendar ownership, notification policy, or Phase 2 planning.

Acceptance:
- A synthetic multilingual evaluation set covers all four categories, multi-signal announcements, no-signal/other, schedule change, assignment DDL, exam/Quiz time, conflicting dates, vague dates, all-day versus timed dates, timezone, long/noisy HTML, adversarial prompt injection, duplicates, and updated announcements.
- Report per-category precision/recall and confusion counts against documented thresholds; zero unconfirmed inferred dates reach Calendar or deadline notifications.
- Repeated unchanged analysis is idempotent and cached by content/prompt/schema/model identity; changed content is re-evaluated without deleting audit history.
- Provider unavailable/disabled/denied never blocks Canvas sync or deterministic display. No payload or response body appears in diagnostics.
- UI and accessibility checks pass in English and Simplified Chinese while source text remains unchanged.
- App Schedule tests prove official Assignment/Quiz deadlines are red plus text/symbol, confirmed inferred dates remain visually distinct, and unconfirmed dates remain absent.
- Full suite, clean/release build, signed app, security/privacy scans, and a user-authorized real Canvas-announcement smoke with privacy-safe aggregate evidence pass. Real private announcement text/output must not enter fixtures, screenshots, logs, or handoff.

Write .agent/handoffs/stage-12.md with PASS, PARTIAL, or BLOCKED and exact evidence. Do not begin Outlook or Stage 13.
