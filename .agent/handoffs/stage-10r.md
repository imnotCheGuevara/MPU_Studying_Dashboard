# Stage 10R handoff

Status: PASS

## Implemented scope

- Rebuilt Today around a Monday-through-Sunday weekly timetable with a 07:00-22:00 spatial axis, proportional duration, deterministic overlap lanes, safe clipping, all-day placement, current-date/current-time emphasis, and previous/current/next week navigation.
- Added a persistent right-hand unread-announcement sidebar with source-owned course/title text, localized relative publication time, the original source link, and a local-only read action. Source, background, last-success, refresh-progress, and manual-refresh status remain secondary.
- Rebuilt Schedule with day, week, and six-week month modes; previous/today/next navigation; date headers; all-day area; time gutter; proportional blocks; deterministic overlap lanes; current-time marker; course/source/type filters; date selection; accessible event details; original source links; undated items; cancellation state; and sync-error presentation.
- Added a reusable calendar-presentation layer. Formal schedule events include course meetings, official deadlines, and confirmed inferred deadlines. Unconfirmed inferred dates remain undated and never become formal events.
- Completed centralized English and Simplified Chinese presentation localization for app-owned navigation, dates, weekdays, months, relative time, status/error/recovery text, progress, controls, menus, dialogs, help, accessibility wording, and empty/loading/error/permission states. Language changes apply at runtime without restart.
- Extended the dashboard read model only for fields already present in unified storage: source URLs and all-day flags. The SQLite schema, connectors, sync/deletion behavior, Calendar ownership, notification policy, AI policy, and privacy clearing were not changed.
- Added explicit synthetic UI-QA launch paths, including an in-memory SQLite-backed non-preview path. Normal launch still constructs `AppEnvironment` production dependencies and reads the real database; fixtures are reachable only through explicit QA arguments.

## Changed files

- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardDataService.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/App/Stage10RQAData.swift` (new)
- `Sources/CampusDashboard/Domain/Models.swift`
- `Sources/CampusDashboard/Features/Announcements/AnnouncementsView.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Schedule/CalendarPresentation.swift` (new)
- `Sources/CampusDashboard/Features/Schedule/ScheduleView.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Features/Shared/SharedViews.swift`
- `Sources/CampusDashboard/Features/Shared/SpatialTimeGrid.swift` (new)
- `Sources/CampusDashboard/Features/Tasks/TasksView.swift`
- `Sources/CampusDashboard/Features/Today/TodayView.swift`
- `Tests/CampusDashboardTests/Stage10DashboardDataTests.swift`
- `Tests/CampusDashboardTests/Stage10RPresentationTests.swift` (new)
- `.agent/handoffs/stage-10r.md` (new)

No central instruction, constraint, execution-rule, roadmap, status, stage-prompt, project-specification, accepted handoff, or Stage 10 handoff was edited. The worktree was entirely untracked at entry; all pre-existing files and user work were preserved.

## Layout and calendar decisions

- Time-grid positions are computed from local calendar boundaries rather than fixed UTC intervals. Events are clipped to the visible day and 07:00-22:00 range while their full localized time remains available through labels/help.
- Events are sorted by start, end, and stable identifier. Intersecting events use the first free lane in a deterministic overlap group, giving identical placement regardless of input order.
- Cross-midnight events are clipped independently on adjacent dates. DST day/week calculations use the selected time zone and local start-of-day boundaries.
- Event kinds use both symbol and color, plus explicit accessibility wording, so course meetings, official deadlines, and confirmed inferred deadlines do not rely on color alone.
- Month mode is a Monday-first 42-cell grid. Selecting a date moves to its detailed day view. Day/week modes share the same time-grid and event-detail model.

## Localization and source-text boundary

Localized app-owned inventory includes primary navigation and titles; day/week/month and date navigation; date/time/month/weekday and relative-time formatting; health, authorization, permission, background, Calendar, notification, AI, diagnostic, and refresh states; task priorities/types; action buttons; menus, dialogs, sheets, help/tooltips; accessibility labels/hints; and empty/loading/error/permission states.

Source-owned course names/codes/terms, meeting titles, task titles, announcement titles/bodies, teacher text, locations, provider/model identity, source display names, and source URLs are never passed through the translation dictionary. Tests compare the entire snapshot across a language switch and explicitly assert course, meeting, task, announcement, location, identity, and URL preservation.

## Automated verification

Successful verbose output is retained under `/tmp/campus-stage10r.oNZcKF`.

```sh
./scripts/test.sh --filter Stage10R
# PASS: 12 tests / 2 suites, 0 failures, 0.013s.

./scripts/test.sh
# PASS: 164 tests / 15 suites, 0 failures, 0.386s.

swift package clean
swift build --jobs 1
# PASS: clean debug build, 39.10s.

./scripts/build-app.sh
# PASS: production build, 42.92s; signed dist/Campus Dashboard.app.

./scripts/verify-app.sh
# PASS: Launch Services application launch and packaged Keychain create/read/delete smoke.

codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS.

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: both files valid.

codesign -d --entitlements - "dist/Campus Dashboard.app"
# PASS: app-sandbox, network-client, and Calendar entitlements present.

! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
# PASS: no credential or private-key pattern found.

ruby -e 'loc=File.read("Sources/CampusDashboard/App/Localization.swift"); keys=Dir["Sources/CampusDashboard/{App,Features}/**/*.swift"].flat_map{|f| File.read(f).scan(/(?:model\.text|Localizer\.text)\("([^"]+)"/).flatten}.uniq.sort; missing=keys.reject{|k| loc.include?(k.inspect)}; abort("Missing localization keys: #{missing.join(", ")}") unless missing.empty?'
# PASS: no missing literal localization key.

rg -n -- '--stage10r-ui-qa|--stage10r-db-ui-qa|SyntheticFixtures|if let scenario|snapshot = \.empty' Sources/CampusDashboard/App/{CampusDashboardApp.swift,DashboardModel.swift,AppEnvironment.swift} Tests/CampusDashboardTests/{Stage10DashboardDataTests.swift,Stage10RPresentationTests.swift}
# PASS after review: fixture assignment exists only behind an explicit preview scenario/QA argument; normal launch uses AppEnvironment. Existing and new tests prove an empty production database stays empty, and the non-preview QA model loads only its inserted SQLite rows through SQLiteDashboardDataReader.

! rg -n '[[:blank:]]+$' Sources/CampusDashboard/App/{CampusDashboardApp.swift,DashboardDataService.swift,DashboardModel.swift,Localization.swift,Stage10RQAData.swift} Sources/CampusDashboard/Domain/Models.swift Sources/CampusDashboard/Features/{Shared/SharedViews.swift,Shared/SpatialTimeGrid.swift,Today/TodayView.swift,Schedule/CalendarPresentation.swift,Schedule/ScheduleView.swift,Tasks/TasksView.swift,Announcements/AnnouncementsView.swift,Confirmations/ConfirmationQueueView.swift,Settings/SettingsView.swift} Tests/CampusDashboardTests/{Stage10DashboardDataTests.swift,Stage10RPresentationTests.swift} .agent/handoffs/stage-10r.md
# PASS.
```

The focused coverage includes proportional position/duration, deterministic overlap ordering, clipping, cross-midnight input, Monday-first navigation, time zones and a 23-hour DST day, 42-cell month boundaries, filters, event detail/source preservation, all-day behavior, unconfirmed-inference exclusion, local announcement-read persistence, runtime language/date formatting, localization inventory, source-text preservation, and the SQLite production-reader boundary. The complete suite preserves all existing data, sync, Calendar, notification, AI, privacy, and security checks.

## Manual signed-app evidence

All observations used explicit synthetic or in-memory SQLite data. No private school screenshot was stored. Source links were verified as actionable links carrying the unchanged synthetic URL; the external browser target was not opened.

| Date (Asia/Macau) | Build / size / language | Evidence |
| --- | --- | --- |
| 2026-09-05 | Signed app, 1180x780, English | Today: Monday-Sunday boundary, proportional overlapping/adjacent and clipped early/late classes, long title, current marker, week navigation, compact status, readable announcement sidebar/read action. Schedule: day/week/month, navigation, filters, month boundary, date-to-day selection, all-day/time grid, details, cancellation/source/accessibility semantics. Empty, error, and permission states inspected. |
| 2026-09-05 | Signed app, 1180x780, Simplified Chinese | Runtime switch updated navigation, dates, weekdays, months, relative time, states, controls, menus, filters, details, Settings, help, and accessibility wording without restart; source-owned synthetic text and URLs remained unchanged. |
| 2026-09-05 | Signed app, 980x680 minimum content size, English | Today and Schedule retained essential controls, scrollable spatial grid, accessible right sidebar, readable overlap semantics, event help, source link, and navigation. |
| 2026-09-05 | Signed app, 980x680 minimum content size, Simplified Chinese | Today and Schedule retained essential controls and sidebar access; day/week/month controls, filters, labels, details, and empty/error/permission presentations remained usable. |
| 2026-09-05 | Final signed app, 980x680, English, non-preview in-memory SQLite | Production reader rendered exactly the inserted course, course meeting, source URL, source health, and unread announcement. Accessibility tree exposed Monday-Sunday headers, real time gutter, current-time marker, course-meeting kind, full time/location help, original source link, and local read action. No preview selector, fixture banner, or known fixture record appeared. |

Interaction checks included previous/next/current week, day/week/month and previous/next/today, month-date selection, course/source/type filters, event-detail sheet, announcement mark-read, keyboard focus, Command-R refresh, and accessibility labels/help for event kind, time, location, clipping, cancellation, controls, and source links. Window preferences changed solely for the size checks were restored afterward.

## Remaining risks and limitations

- At the minimum width, a dense multi-lane event may visually truncate its long title. Full source-owned text, time, and location remain available in the event detail sheet and accessibility help; essential controls do not clip.
- Source-link destinations were inspected as actionable original URLs but not opened, avoiding an unnecessary external browser/network side effect during synthetic QA.
- OS-owned menu and window-control wording follows the active macOS localization and is outside the app-owned string catalog.

## Stage boundary

Stage 10 remained **PAUSED** for the entire repair. The seven-day trial was not started or resumed, and **zero trial days were counted**. Only the main project conversation may accept this handoff and authorize Stage 10 to resume.
