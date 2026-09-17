# Stage 16M — Manual events

Status: PASS
Updated: 2026-09-15 Asia/Macau

## Result

User-requested macOS manual-event feature is implemented. Schedule has Add event; event details have Edit event and confirmed Delete event. Fields: title, start/end, all-day, location. The all-day editor uses an inclusive last date and persists an exclusive end. Events appear in Schedule and Today. Schema 16 adds an independent manual_events table. School sync cannot overwrite these records; no Calendar outbox, AI, notification or school-system operation is introduced. Clear local user state also deletes manual events and removes them from the current model.

Changed implementation files: App/DashboardModel.swift, App/Localization.swift; Features/Schedule/{ManualEvent.swift,ManualEventEditor.swift,CalendarPresentation.swift,ScheduleView.swift}; Features/Shared/SpatialTimeGrid.swift; Features/Today/TodayView.swift; Persistence/{SQLiteDatabase.swift,DatabaseMigrator.swift,Repositories.swift}; Privacy/PrivacyDiagnosticsService.swift. Tests: ManualEventTests.swift, PersistenceTests.swift. Central context and stage-16m scope updated for this user-authorized addition.

Five pre-existing modifications in ProductionSyncRunner.swift, SIwebConnector.swift, SyncEngine.swift and the two corresponding connector/sync test files were preserved. The candidate necessarily includes the current working-tree versions; no claim of an isolated source commit is made.

## Evidence

- ./scripts/test.sh: PASS, 248 tests / 21 suites. Covers disk reopen/update/delete, invalid input preservation, cross-midnight/exclusive end, filters, zero Calendar outbox work, privacy deletion. Initial table-inventory expectation was updated for the new table; full suite passed again after final product edits.
- ./scripts/build-app.sh dist/manual-events: PASS, Release and ad-hoc signature.
- ./scripts/verify-app.sh with absolute candidate path: PASS, app launch and Keychain smoke. An initial relative-path call failed at defaults path resolution; absolute-path retry passed.
- codesign --verify --deep --strict 'dist/manual-events/Campus Dashboard.app': PASS.
- git diff --check: PASS.
- Candidate launched with --stage10r-ui-qa (in-memory synthetic data). Native UI verified empty-title Save disabled; creation appeared in week grid; details opened edit/delete controls; editing title and converting to all-day saved successfully; Today showed the edited event with count increasing from 7 to 8. Screenshot visually inspected. Preview then quit. Actual UI deletion was not exercised; repository deletion and privacy deletion are automated-test verified.

## Delivery and limits

Candidate: /Users/yang/Documents/ChatGPT/Studying_Dashboard/dist/manual-events/Campus Dashboard.app.
Delivery follow-up: the user was still running the previous dist app. Quit it and copied the verified candidate into the usual dist/Campus Dashboard.app location. The previous bundle is preserved at dist/backups/2026-09-15-before-manual-events/Campus Dashboard.app. Strict signature verification passed after copying. Normal launch succeeded with existing local data; native UI confirmed the user opened the manual-event editor. No interaction with their draft was performed. Other installed copies remain unchanged. No live personal event or Calendar mutation was performed. macOS only; Windows Preview 3 assets are unchanged. Manual events do not create Apple Calendar events or reminders. The candidate retains the existing version metadata and ad-hoc identity; a rebuild may require Calendar reauthorization separately. Normal production launch is now verified; ongoing daily-use acceptance remains separate. No new dependent stage is authorized by this handoff.

## End-time interaction follow-up — 2026-09-15

Per the user's clarification, every start-date/time edit now resets the editor end to the same start (start of day for all-day events). The end picker cannot select an earlier value. Timed events still require a positive duration before Save is enabled; all-day events allow the same displayed date. Invalid ranges also disable Save, with repository validation retained.

Final checks: 248 tests / 21 suites PASS; separate Release build PASS; verify-app launch/Keychain smoke PASS; copied app strict signature and diff whitespace checks PASS. An earlier in-flight build was invalidated by the user's clarified edit and was rerun successfully. Updated the usual dist app, preserving the preceding bundle at dist/backups/2026-09-15-before-end-time-constraint/Campus Dashboard.app. Normal launch and blank editor opening verified. Live date-stepper verification was interrupted by concurrent user UI changes; no draft was saved or user event modified during this check.
