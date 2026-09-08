# Stage 15S handoff — section-aware schedule-change targeting safety repair

Status: `PARTIAL`

## Outcome

The Stage 15S implementation is complete and all local, synthetic, build, packaging, signature, privacy, notification, presentation, and Calendar-boundary gates pass. Course cancellations and other schedule changes now fail closed unless the affected date role, enrolled SIweb section, proposed meeting ID, persisted target ID, and current unique SIweb meeting all agree. A manual correction only saves a pending proposal; a fresh exact Calendar preview and a separate explicit confirmation are required before the existing course meeting can be modified.

The stage remains `PARTIAL` because the real signed-app source walkthroughs did not complete and the real app database has not been migrated or processed. Launching the normal real-data path could consume existing Calendar reconciliation work, so it was intentionally not run without action-time confirmation from the main conversation. No real EventKit create, update, cancellation, or deletion was attempted. Stage 10 remains paused.

## Root cause

- The prior provider contract did not distinguish the affected class meeting from a make-up option, response deadline, another section, or an ambiguous date.
- Target resolution accepted a sole candidate without checking the provider date, and otherwise used a broad twelve-hour window. In a multi-date announcement, a Friday date could therefore be associated with a Monday meeting.
- Course-reconciliation could clear a vanished target while retaining a `confirmed` or `corrected` decision.
- Manual schedule correction could become confirmed at save time, without a target-bound preview token.
- Calendar, outbox, and Schedule presentation still admitted a targetless confirmed schedule change as a standalone event.

## Implemented

- Added provider schema/prompt v4 fields for schedule date role, affected section, and proposed target meeting ID. Provider output is rejected unless an `affected_meeting` proposal exactly matches the locally supplied section, meeting ID, course family, and meeting date/time. Make-up, response-deadline, other-section, ambiguous, conflicting, or nonmatching proposals cannot target a meeting.
- Added one shared deterministic target resolver. Timed meetings require an exact candidate within five minutes; all-day values must be the same local calendar day. Runtime paths revalidate the role, section, proposal ID, resolved ID, active SIweb meeting, confirmed one-to-one course mapping, and uniqueness.
- Changed manual schedule repair to save as `pending`. It records the uniquely resolved local SIweb meeting as a proposal, then requires a read-only preview carrying the exact meeting ID and signal update timestamp. Confirmation rejects stale previews or any target that no longer revalidates.
- Changed reconciliation so a confirmed/corrected schedule result whose target or targeting metadata no longer validates returns to `pending` / `pending_review`, records an append-only `target_invalidated` audit entry, and queues scoped restoration only for an existing app-owned binding.
- Added schema v14. Every legacy v13 confirmed/corrected schedule result is conservatively downgraded because v13 cannot contain the new date-role proof. Existing course-meeting or legacy standalone bindings receive scoped recovery work before the stale target is cleared.
- Removed standalone schedule-change eligibility from Calendar reconciliation, Calendar draft creation, notification/outbox eligibility, and Schedule presentation. Reconciliation can only update/cancel the uniquely revalidated SIweb `course_meeting`; targetless, ambiguous, stale, or metadata-corrupted records produce no new event or notification.
- Preserved the existing dedicated-Calendar ownership checks, append-only audit, undo/restoration behavior, source fields, exam/deadline visual semantics, Keychain-only secrets, minimum-data provider boundary, and dormant Outlook boundary. Added bilingual correction/section/date-role guidance.

## Synthetic safety evidence

- Multi-section and multi-date provider fixtures cover the intended Monday meeting plus a Friday distraction, wrong section, wrong meeting ID, make-up date, response deadline, ambiguity, and conflicts. Only the exact affected meeting resolves.
- The Calendar lifecycle fixture records write counts: preview and pending reconciliation perform zero writes; a fresh target-bound confirmation cancels only the exact existing course meeting; undo restores it; a forced confirmed/no-target row and a confirmed row with corrupted targeting metadata perform no create/update/cancel operation.
- Reconciliation fixtures prove that target disappearance returns confirmed state to pending with audit evidence and scoped recovery work.
- The v13 migration fixture includes both targetless and formerly targetful confirmed schedule rows. Both become pending/no-target, retain user correction fields, receive valid audit UUIDs, and an existing meeting binding receives a decodable exact-object recovery envelope.
- Existing exam, deadline, notification, accessibility, localization, source-provenance, and Calendar ownership tests remain green.

## Verification performed

- `./scripts/test.sh --filter 'CourseReconciliationTests|PersistenceTests|AcademicSignalTests|CalendarIntegrationTests'` — PASS, 63 tests in 4 suites.
- `./scripts/test.sh --filter 'NotificationBackgroundTests|Stage10RPresentationTests'` — PASS, 30 tests in 3 suites, including notification, timetable/Calendar presentation, localization, and source-preservation coverage.
- `./scripts/test.sh` — PASS, 241 tests in 20 suites.
- `./scripts/build-app.sh` — PASS, production application rebuilt and ad-hoc signed.
- `./scripts/verify-app.sh` — PASS, `com.campusdashboard.desktop` launched as a macOS application and completed the Keychain smoke test.
- `codesign --verify --deep --strict "dist/Campus Dashboard.app"` — PASS.
- `git diff --check` — PASS before this handoff.
- Targeted credential/private-content scan — PASS after review. Matches were limited to a URL password rejection check and an explicitly synthetic sanitization fixture; no credential-shaped value or real announcement body is present in the changes.
- Outlook/Graph/mail-path diff scan — PASS, no matching production change. No Outlook authorization, token access, callback, or network request was run.

## Release identity

- Bundle: `dist/Campus Dashboard.app`
- Bundle identifier: `com.campusdashboard.desktop`
- Version/build: `0.3.0 (4)`
- Signature: ad-hoc; strict verification passed
- Executable SHA-256: `956abdc49a1dfa3742a00080c0da902429368d4a6b7c9ed3cd21aced9b6bf5f0`
- CDHash: `95d7a377b85eb1569ed1d0c9858a2a6e34d2feed`

## Real read-only evidence and remaining gates

- A signed-app Canvas read-only smoke produced no result before it was stopped after more than three minutes; it emitted no source content.
- A signed-app SIweb read-only smoke reached its 60-second timeout and exited with status 142; it emitted no source content.
- A query-only aggregate inspection of the app database found schema version 13 and four active confirmed schedule-change rows without a target. It also found zero standalone schedule Calendar bindings and zero schedule notification deliveries. No row content, title, body, URL, credential, token, or personal Calendar detail was read or recorded.
- The real database was deliberately left unchanged. The tested v14 migration is expected to downgrade those four legacy rows, but normal signed-app migration plus queued Calendar cleanup must be observed only after the main conversation gives action-time approval for any potential EventKit effect.
- Still required for acceptance: complete the signed-app Canvas/SIweb read-only walkthrough; launch and inspect the v14 migration using aggregate state only; verify the bilingual pending/correction/exact-preview UI; and, with explicit action-time approval, exercise the existing dedicated Campus Dashboard calendar's exact-meeting confirm/undo lifecycle. The handoff must remain `PARTIAL` until these mandatory real checks pass.

## Changed files

- AI contract, targeting, persistence, and provider boundary: `AcademicSignalModels.swift`, `AcademicScheduleTargetResolver.swift`, `AcademicSignalCoordinator.swift`, `AcademicSignalPersistence.swift`, `DeepSeekProvider.swift`.
- Reconciliation and storage: `CourseReconciliation.swift`, `DatabaseMigrator.swift`, `SQLiteDatabase.swift`.
- Calendar, notification, and presentation gates: `CampusCalendarService.swift`, `OutboxProcessor.swift`, `CalendarPresentation.swift`, `ReleaseReadiness.swift`, `DashboardModel.swift`.
- User correction and confirmation UI: `AnnouncementsView.swift`, `ConfirmationQueueView.swift`, `Localization.swift`.
- Synthetic regressions: `AcademicSignalTests.swift`, `CalendarIntegrationTests.swift`, `CourseReconciliationTests.swift`, `PersistenceTests.swift`.

## Proposed main-conversation update

- Keep Stage 15S as `PARTIAL`: implementation and synthetic gates complete; real source/UI/migration/EventKit lifecycle still pending.
- Do not accept Stage 15S or authorize Stage 10 from this delegated task.
- Before any real Calendar mutation, obtain fresh action-time confirmation and constrain the walkthrough to the existing dedicated Campus Dashboard calendar and the single previewed SIweb meeting.

No central control file was edited, no commit was created, and no future stage was started.
