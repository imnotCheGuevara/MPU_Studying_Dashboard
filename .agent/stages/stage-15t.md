# Stage 15T — Information-noise reduction and Needs Review center

Status: `ACCEPTED`

## Goal

Remove duplicate work between Announcements and the AI review surface, and conservatively suppress empty Canvas assignment shells until they become actionable. This is a pre-release repair; it must not weaken Stage 15S schedule targeting, date confirmation, Calendar isolation, or read-only source boundaries.

## Required startup context

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the relevant UI/correction/remaining-gate sections of `.agent/handoffs/stage-15s.md` located with `rg -n`. Read older material only for a named gap, using `rg -n` followed by narrow `sed -n`.

The implementation task may change product code and tests needed for this stage plus `.agent/handoffs/stage-15t.md`. It must not edit central control files. Begin from the committed `main` baseline and preserve all Stage 15S behavior.

## Implementation scope

### Announcements and Needs Review

- Announcements remains the complete source feed: course grouping, unread state, original title/body, source link, and a compact AI/status indicator remain available.
- Rename the user-facing AI confirmation queue to **待确认** / **Needs Review**. Its badge and list contain only unresolved items requiring a user decision or correction, including ambiguous/conflicting results, inferred-date confirmation, provider-unavailable fallback requiring correction, and actionable `other` results that have not been resolved.
- Confirmed, rejected, ignored, or otherwise resolved items leave Needs Review but remain visible in Announcements. Ordinary high-confidence informational suggestions must not occupy the queue.
- Provider-unavailable and `other` items must retain a usable correction path and must never silently disappear while unresolved.
- Use one canonical persisted signal and action path; do not create duplicate copies of announcement content. Keep both surfaces consistent after confirm, correct, reject/ignore, undo, refresh, and restart.

### Empty Canvas assignment shells

Classify an item as a local `placeholder` only when deterministic source evidence shows **all** of the following: no official due date; no meaningful description/instructions; no attachment; no quiz, external-tool, or other source-linked activity; no currently available meaningful submission route/type; and no explicit offline, reading, preparation, attendance, or other actionable requirement. AI must not make this decision.

- Absence of an online submission type alone is never enough to hide an item. A due date or any meaningful offline/reading/instruction signal keeps it visible.
- Preserve placeholders in SQLite and preserve their source links and identities. Never delete them or write any state back to Canvas.
- Exclude placeholders from normal Today/task lists, AI provider payloads/processing, Calendar events, deadline reminders, and new-task notifications. Show them in a collapsed per-course **暂存占位作业** / **Placeholder assignments** group with count, expand control, and a persisted local “always show” override.
- Re-evaluate on every upsert/sync and after restart/migration. If a due date, meaningful instructions, attachment, quiz/external activity, submission availability/type, or other actionable source evidence appears, reactivate the same stable task automatically. It must enter normal views exactly once without duplicate task, Calendar, AI, or notification effects.
- Existing stored assignments must be recomputed safely without deletion. Fail open to normal visibility when source evidence is incomplete or parsing is uncertain.

### Honest product metrics

Record only local aggregate counts needed to measure placeholder suppression and reactivation. If a time-saved estimate is shown or exported, document its explicit formula and label it as an estimate. Never invent accuracy, time-saving, or resume claims from synthetic tests.

## Prohibited changes

- No Canvas/SIweb writes, new credentials, secret handling, mailbox integration, proxy or FlClash changes, or external training/upload of user corrections.
- No direct AI control of Calendar/notifications and no Calendar eligibility for unconfirmed inferred dates.
- No modification/deletion outside the dedicated Campus Dashboard calendar. No real EventKit mutation during automated testing or walkthrough without fresh action-time user approval.
- Do not resolve the remaining Stage 15S real lifecycle gate in this task, begin the seven-day trial, freeze a release, or claim Stage 15/15R/15S acceptance.

## Required verification

- Add a table-driven placeholder eligibility matrix covering every positive signal, incomplete evidence, no-submission offline/reading work, and truly empty shells.
- Prove persistence/restart, repeated-sync idempotency, historical recomputation, persisted override, placeholder-to-active transition, and exactly-once downstream behavior.
- Prove placeholders generate no AI/provider request, Calendar/outbox operation, deadline/new-task notification, or normal-list row.
- Prove Needs Review filtering, badge counts, provider-unavailable correction, `other` correction, resolution removal, and Announcements retention across restart.
- Regress Stage 15S exact-meeting cancellation, make-up event, inferred-date confirmation, exam styling, dedicated-calendar isolation, source read-only behavior, bilingual localization/accessibility, and mailbox-path absence.
- Run focused tests while developing, then the full suite, production build, app verification, strict signature verification, `git diff --check`, and targeted credential/private-data/prohibited-network scans. Perform a synthetic bilingual signed-app walkthrough without exposing real source text.

## Acceptance and handoff

Write `.agent/handoffs/stage-15t.md` with changed files, migrations/model semantics, exact commands and concise results, UI evidence, limitations, and privacy-safe metrics evidence. Mark it `PASS`, `PARTIAL`, or `BLOCKED`; `PASS` requires every mandatory automated and available synthetic/manual check above. Do not edit `.agent/CURRENT.md`, `.agent/STATUS.md`, `.agent/ROADMAP.md`, or any other central control file. Stop after the handoff and await main-conversation acceptance.
