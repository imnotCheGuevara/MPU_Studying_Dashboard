# Stage 15 — Final integration and release candidate

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and `.agent/handoffs/stage-12.md`. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

## Prerequisite gate

Stages 10R and 12 must be accepted, Stage 10 must remain paused at 0/7, and Stage 15 must be explicitly READY or IN PROGRESS. Outlook Stages 13–14 must remain paused/deferred. Confirm the exact state in `.agent/CURRENT.md`; otherwise stop without implementation.

## Stage contract

You own Stage 15 only: final integration hardening, acceptance repair, and release-candidate freezing for the accepted Canvas, SIweb, DeepSeek Canvas-announcement classification, Apple Calendar, notifications, local storage, privacy, diagnostics, localization, and background-sync scope.

Exercise the complete supported workflow together on the final signed app. Fix only acceptance-affecting defects inside this approved scope and add regression tests. Verify independent source failures, manual/hourly sync, restart/offline/sleep recovery, DeepSeek opt-in/rotation/revocation/rate-limit behavior, confirmation gating, Calendar and notification reconciliation, local clearing, localization, accessibility, performance, and earlier-stage regressions.

Outlook is excluded. Its dormant code and offline evidence may remain in the repository, but the release candidate must leave it disabled and unconfigured and must make no Outlook authorization, Microsoft Graph, or mail request. Do not implement, repair, remove, authorize, or test Outlook functionality beyond a focused assertion that it remains dormant. Do not send Outlook data to DeepSeek.

The following field defects are acceptance-affecting and are explicitly in scope:

- An obvious cancellation notice such as `Class cancellation ...` must be recognized by deterministic multilingual rules as `course_schedule_change` even when DeepSeek is unavailable; provider failure must retain a useful deterministic result and reason.
- Preserve the already accurate high-confidence path and avoid broad classifier rewrites. First identify and expose the actual provider-unavailable category (configuration/consent, missing Keychain key, connection or exact-host routing, HTTP status/rate limit, timeout, decoding/schema, budget, or other safe category), provide a privacy-safe recovery action, and regression-test each branch.
- Every result, including `other`, conflict, and provider-unavailable fallback, must offer a usable local correction flow. The user can correct type, actionable fields, dates/times, and course association, then review, confirm, undo, or reset the correction without changing Canvas.
- The known UI/data gap is that correction controls are currently attached only to emitted signal records; an `other` analysis with an empty signal array leaves no correctable record. Repair the analysis-level empty-result flow instead of treating reprocessing as correction.
- Corrections must feed a local, auditable, reversible personalization layer. Treat corrections as supervised feedback, not autonomous or opaque “unsupervised training”: retain provenance and versioning, prefer deterministic/course-local rules or reranking, prevent one correction from silently rewriting unrelated records, and never upload correction history or retrain a remote model without a separate future consent gate.
- A high-confidence schedule-change or exam signal may appear immediately as a local candidate, but any date inferred from announcement text still requires explicit confirmation. Only after confirmation may the normal sync service create/update/cancel the corresponding in-app and dedicated Apple Calendar event, idempotently and with an undoable preview.
- Exam events must be visually distinct in the app using an accessible color plus a non-color label/icon. Because EventKit does not provide a reliable per-event color within one calendar, keep Apple Calendar inside the single dedicated calendar and distinguish exams there by an explicit event type marker/title or notes; do not create or recolor unrelated calendars.
- Add reproducible, privacy-safe measurements: before/after labeled-fixture accuracy (including per-class precision/recall and schedule/exam recall), fallback recovery and correction rates, duplicate/unsafe-write counts, and a timed workflow comparison for estimated manual time saved. Never fabricate resume metrics; record the sample, method, denominator, and limitations.

Allowed scope: integration wiring and narrowly necessary fixes for the accepted Canvas/SIweb/DeepSeek/Calendar/notification behavior, including the field defects above; local schema/migrations and UI needed for correction/personalization; regression and end-to-end fake-service tests; release build/signing verification; privacy/security scans; aggregate-only real-service smoke; and `.agent/handoffs/stage-15.md`. Do not start the seven-day counter, begin Stage 10, expand learning beyond user corrections, or begin Phase 2 study coaching.

Acceptance:

- The full automated suite and end-to-end fake-service scenarios pass, including simultaneous source/DeepSeek failures without corruption, duplicate side effects, or cross-source blocking.
- Real authorized Canvas and SIweb smoke, plus synthetic and user-authorized Canvas-announcement DeepSeek smoke, pass with aggregate-only evidence.
- Official and inferred dates remain distinct; no unconfirmed inference reaches Calendar or deadline notifications.
- Deterministic English and Simplified Chinese cancellation fixtures remain correctly classified when DeepSeek succeeds, fails, or is disabled. `other` and provider-unavailable results are correctable, persist across restart, display provenance, and support undo/reset.
- A held-out labeled fixture report demonstrates the baseline and post-repair result without leakage, including per-class metrics. Personalization improves the corrected pattern on a separate replay case without degrading protected safety/date-gate tests.
- Confirmed schedule changes and exams reconcile to the in-app calendar and the dedicated Apple Calendar without duplicates; unconfirmed items do not. Exams have an accessible distinct in-app treatment and a non-color Apple Calendar marker.
- Apple Calendar writes remain confined to bound events in the dedicated Campus Dashboard calendar; repeated reconciliation creates no duplicate events or notifications.
- DeepSeek sends only consented minimum Canvas announcement fields, uses Keychain credentials and exact-host routing, and remains safely disableable.
- Outlook is disabled/unconfigured and produces no authorization, Graph, mail, or DeepSeek traffic.
- Credential, payload, response, diagnostics, fixture, Calendar-ownership, and prohibited-network scans pass.
- English and Simplified Chinese UI, accessibility, responsiveness, clean/release build, app verification, and code signing pass.
- The handoff includes reproducible aggregate metrics and an evidence-based time-saved estimate suitable for later resume wording, with no private source text or invented claim.
- A reproducible signed release candidate is identified by build commands, SHA-256 and signing identity/CDHash in the handoff. No feature change is allowed before Stage 10 without invalidating the freeze.

Write `.agent/handoffs/stage-15.md` with `PASS`, `PARTIAL`, or `BLOCKED`; changed files; commands and concise results; aggregate real-service evidence; Outlook-dormancy evidence; defect/fix and correction-learning evidence; calendar/exam evidence; measurement method/results; frozen release-candidate identity; and remaining risks for Stage 10. Do not include private announcement text. Do not begin Stage 10 or the seven-day trial.
