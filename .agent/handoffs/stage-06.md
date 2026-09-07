# Stage 06 handoff

Status: PASS

## Main-thread acceptance repair

The first Stage 06 review found a mandatory defect: `CalendarBinding` persisted
`external_event_identifier`, but neither the EventKit adapter nor the calendar
service used it. If a full iCloud/Calendar synchronization changed
`calendarItemIdentifier`, an update outside the marker time window could create
a duplicate and a cancel could mark the binding removed while leaving an orphan.

This repair adds calendar-scoped external-identifier recovery and changes the
existing-binding rules to fail closed. An active binding whose internal ID is
missing can no longer fall through to ordinary creation or be marked removed.
It must recover one unique event whose external ID, ownership marker, dedicated
calendar ID, and calendar source ID all match. The repaired internal/external
identifiers are persisted before subsequent work. Zero candidates, multiple
candidates, a foreign calendar/source, or a marker mismatch do not modify any
event and do not complete the removal.

## Scope delivered

- Added a production EventKit adapter behind a Sendable/testable `CalendarEventStore` boundary. Full event access is requested only by the explicit Settings action or the explicitly invoked local smoke test; startup and outbox processing never trigger a permission prompt.
- Added Settings controls to request/refresh permission, choose an EventKit source, create a dedicated `Campus Dashboard` calendar, or explicitly select an existing dedicated writable calendar. The UI distinguishes iCloud, local, CalDAV, Exchange, and other sources and does not present Notification or AI controls as active.
- Added schema migration v4 and `managed_calendar_identity`. It persists the internal calendar UUID, EventKit calendar identifier, source identifier/type/title, calendar title, app-created versus user-selected state, ownership marker, validation state, and last successful verification time.
- Added durable `CalendarBinding` persistence for every managed event, including EventKit event/external identifiers, per-event ownership marker, calendar/source identifiers, sync state, and last verification time.
- Added `CalendarEventStore` lookup by external identifier. The production adapter uses EventKit's `calendarItems(withExternalIdentifier:)`, filters results to the already verified dedicated calendar and its source before returning them, and excludes reminders/non-event items.
- Added strict internal-ID recovery for existing bindings. Update and cancel require exactly one external-ID candidate, then independently validate the candidate's external ID, exact ownership marker, calendar ID, and source ID. Multiple candidates fail closed and titles are never considered.
- Added safe handling when an external identifier is unavailable. An update may use the existing dedicated-calendar, exact-marker, narrow time-window lookup only when it yields one candidate; it never creates after a failed active-binding recovery. Cancel has no time basis and therefore fails closed instead of claiming removal.
- Added final mutation-time revalidation inside the EventKit adapter. Updating or removing an existing item rechecks its calendar, source, marker, and external ID immediately before the EventKit write, protecting against a change between service resolution and mutation.
- Added strict validation before every event side effect. Calendar identifier, source identifier, writability, binding calendar/source identity, and ownership marker must all agree. A stale binding or marker mismatch fails closed and cannot modify or delete the discovered EventKit item.
- Added safe missing-identifier behavior. Matching title/source calendars are returned only as recovery candidates; the app never auto-adopts one by title, even if there is only one candidate. Multiple same-name candidates are explicitly ambiguous and require user selection.
- Added database-backed mapping for eligible future course meetings and learning-task deadlines. Official dates are accepted. A suggested/inferred date is rejected at the Calendar boundary unless `suggestion_confirmed_at` is present. Announcements, unknown object types, and undated items are rejected.
- Implemented create, update, and cancel through the Stage 05 durable outbox `CalendarService` boundary. Updates use binding identity, never title search. Cancels are no-ops without a valid binding and are repeatable after a successful removal.
- Closed the side-effect/binding crash window: when an EventKit save succeeds before the binding commit, retry searches only the configured dedicated calendar, near the expected event time, for the exact stable ownership marker and adopts one unique match. It never searches or mutates other calendars. Multiple marker matches fail closed.
- Added a signed-app `--calendar-smoke-test` flow that creates a uniquely named app-owned Stage 06 test calendar, verifies create/update/repeated-sync/cancel through the production EventKit adapter, and then removes that test calendar.

## Changed files

- `Package.swift`
- `Resources/Info.plist`
- `Resources/CampusDashboard.entitlements`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/Calendar/CalendarModels.swift`
- `Sources/CampusDashboard/Calendar/CalendarPersistence.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Calendar/EventKitEventStore.swift`
- `Sources/CampusDashboard/Calendar/CalendarLocalTool.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Tests/CampusDashboardTests/CalendarIntegrationTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `.agent/handoffs/stage-06.md`

No project constraint, roadmap, status, stage prompt, project specification, or earlier-stage handoff was edited.

## Acceptance evidence

| Acceptance item | Evidence/result |
| --- | --- |
| Permission denied and revoked | PASS — fake-store tests prove denial blocks setup, revocation preserves configuration/bindings, outbox work remains pending, and restored access replays once. Other app state is independent. |
| Dedicated calendar create/select | PASS — tests verify the exact EventKit identifier returned from the chosen source is persisted, with app-created/user-selected state and internal UUID. The Settings action is explicit. |
| Duplicate names and lost calendar identifier | PASS — one or multiple same-source/title candidates are never auto-adopted; multiple candidates record `ambiguous`; all recovery requires explicit selection. |
| Local versus iCloud identity | PASS — automated tests persist and report both source kinds. The real-Mac test used the available iCloud source. |
| Unwritable/source-changed calendar | PASS — unwritable selection and validation fail closed; exact persisted source identity is required on every operation. |
| Per-event binding and stale binding protection | PASS — bindings persist event/external IDs, ownership marker, calendar/source IDs, state, and verification time. Tests corrupt both binding calendar identity and the EventKit-side marker; neither case removes the event. |
| Internal event identifier invalidation | PASS — fake tests replace the EventKit internal ID while retaining external ID/marker. Update recovers the same event even after its date moves ten days, retains one event, and persists the new internal ID. Cancel recovers and removes the original event, then records the new IDs with `removed` state. |
| External identifier scope and ambiguity | PASS — a matching external ID in another calendar is not returned for recovery; a wrong marker is rejected; two same-calendar external-ID candidates fail closed without title selection or mutation. |
| Missing external identifier | PASS — one exact-marker candidate within the dedicated-calendar time window can repair the binding. If the date is outside that window, or cancel lacks a safe lookup basis, recovery fails closed and no duplicate/removal claim is produced. |
| Event create/update/cancel | PASS — task and course-meeting tests create and cancel only bound events. The task lifecycle test updates the same event identifier and retains one event. |
| Outbox retry/replay idempotency | PASS — permission failure retries after restoration; completed work deliberately replayed after deleting its binding (simulated save-before-binding crash) adopts the marker-matched event and keeps exactly one event. |
| Unconfirmed inferred date gate | PASS — a task with only `suggested_complete_at` is rejected until `suggestion_confirmed_at` is stored, after which exactly one event is created. |
| Unrelated calendar/event protection | PASS — automated lifecycle seeds an unrelated event in a different calendar and verifies it survives create/update/replay/cancel unchanged. Production queries and writes always pass the exact configured calendar identifier. |
| Real Mac EventKit lifecycle | PASS — signed app used a newly created, uniquely named dedicated Stage 06 test calendar on the iCloud source; create, update, repeated sync, and cancel passed. The app then deleted only that app-created test calendar. |
| Stage boundary | PASS — no UserNotifications, background scheduler, AI implementation, iPhone verification, or seven-day trial was added. |

## Commands and results

```sh
swift package clean && swift build --jobs 1
# PASS: clean debug build completed in 32.86s.

./scripts/test.sh --filter CalendarIntegrationTests
# PASS: 14 tests covering permission denial/revocation/recovery, calendar creation,
# duplicate/lost identifiers, local/iCloud, unwritable calendars, task/meeting
# lifecycle, outbox replay, stale bindings, internal-ID replacement,
# external-ID scope/ambiguity, missing-external fallback, and inferred-date confirmation.

./scripts/test.sh --filter PersistenceTests
# PASS: 10 tests, including fresh v4 and conservative v3 -> v4 migration.

./scripts/test.sh
# PASS: 93 tests in 8 suites.

./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS after the recovery repair: release app built in 6.31s, signed, launched,
# and completed the packaged Keychain smoke.

open -n -W "dist/Campus Dashboard.app" --args --calendar-smoke-test \
  "/Users/yang/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/calendar-stage-06-repair-final-smoke-b8d39e20.txt"
# PASS: production EventKit lifecycle, forced external-ID recovery, and cleanup.

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
codesign -d --entitlements - "dist/Campus Dashboard.app"
# PASS: Calendar full-access usage description is valid; signed app contains
# app-sandbox and personal-information.calendars entitlements.

! rg -n '^import (UserNotifications|ServiceManagement)|UNUserNotificationCenter|SMAppService|OpenAI|Anthropic' Sources Tests
! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '[[:blank:]]+$' Sources/CampusDashboard/Calendar Tests/CampusDashboardTests/CalendarIntegrationTests.swift Sources/CampusDashboard/App/DashboardModel.swift Sources/CampusDashboard/Features/Settings/SettingsView.swift Resources Package.swift
git diff --check
# PASS: stage-boundary, credential, whitespace, and diff checks were clean.
```

## Real Mac manual/integration check

The signed release app was explicitly launched with the Stage 06 smoke-test action. The sanitized result was:

```text
PASS source=icloud create=1 update=1 cancel=1 repeated_sync=1 external_recovery=1 isolated_calendar=1
```

The repaired flow created a calendar named `Campus Dashboard — Stage 06 Test <random suffix>` using the selected iCloud source and operated only through that returned calendar identifier. After the initial event save, it deliberately replaced the persisted internal EventKit ID with a synthetic stale value and moved the official date ten days—outside the marker lookup window. The production adapter recovered the unique event by external ID plus calendar/source/marker, updated the original event, persisted the current IDs, kept one event through repeated synchronization, cancelled that same binding, and removed only the newly app-created test calendar. No existing calendar was selected for writes and no event outside the test calendar was queried for mutation. No real course content, account identifier, calendar identifier, or event identifier was recorded in the repository or handoff.

## Remaining limitations

- iPhone/iCloud arrival verification belongs to Stage 10 and was not performed or claimed here. The real Mac test did validate EventKit against an iCloud calendar source only.
- Local-source behavior is covered by the fake adapter tests. This Mac did not expose a local source ahead of iCloud during the real smoke flow, so no second real local calendar was created merely to broaden the test.
- Missing EventKit calendar identifiers intentionally require explicit reselection. The implementation does not attempt unsafe automatic recovery from a title match.
- If both EventKit identifiers are unavailable and an exact marker cannot be found uniquely in the dedicated calendar's narrow update window, the binding remains unresolved for user repair. This is intentional fail-closed behavior; cancel never claims success without locating and validating the bound event.
- Stage 05 still owns sync orchestration and Stage 07 will own scheduling. This stage supplies the production Calendar outbox consumer and Settings configuration flow; it does not add a background runner.
- User edits to app-managed fields on a bound event are restored by the next official upsert. Events without the exact app-owned binding and marker are never adopted or changed.

## Handoff conclusion

The main-thread EventKit identifier-recovery defect is repaired. All mandatory Stage 06 automated and real-Mac acceptance items were re-executed and passed. Stage 06 remains marked `PASS`; only the main project conversation may inspect and accept it or authorize the next dependent stage.
