# Stage 10 handoff

Status: PARTIAL

## Scope and privacy boundary

Stage 10 owns real-device acceptance and the seven-day Phase 1 operational trial only. Phase 2 AI study coaching is out of scope. All evidence below must remain aggregate and privacy-safe: do not record credentials, school or Canvas URLs, account or object identifiers, course names/codes, event titles, assignment or announcement text, locations, screenshots containing school content, notification bodies, cookies, tokens, or raw service responses.

The central plan added Stages 11-15 after this stage. They remain `LOCKED` and are not part of this acceptance baseline: Stage 10 must not implement, configure, call, or trial DeepSeek or Microsoft Graph/Outlook, and none of their future results count toward this seven-day record.

Use only the signed `dist/Campus Dashboard.app`, the user's own authorized read-only Canvas and SIweb access, a dedicated writable iCloud calendar selected by identifier in Campus Dashboard, and the user's own iPhone signed into the same iCloud account. Credentials must be entered only through the app's hidden/interactive authorization flows and never through chat, command arguments, logs, screenshots, or this handoff.

## Acceptance checklist

Record `PASS`, `FAIL`, or `BLOCKED` beside every item, with a dated evidence reference. Do not mark this handoff `PASS` until every mandatory item is `PASS` and all seven daily records are complete.

### Preflight and safe setup

- [x] `P01` Final complete automated suite passes before real-device work.
- [x] `P02` Fresh signed app builds, verifies, launches, and has the expected sandbox, Calendar entitlement, and usage descriptions.
- [x] `P03` Canvas read-only smoke returns aggregate success without exposing content or identifiers.
- [x] `P04` SIweb read-only smoke returns aggregate success without exposing content or identifiers.
- [ ] `P05` Campus Dashboard has full Calendar access and a dedicated writable **iCloud** calendar is explicitly created or selected; a local-only source is not accepted for iPhone testing.
- [x] `P06` Notification access and the master switch are enabled for the timed-notification checks.
- [x] `P07` Automatic sync is enabled and macOS Login Items reports the background item enabled or explicitly approved on the final Stage 10R build.
- [ ] `P08` Before-counts are revalidated for the dedicated calendar, one unrelated control calendar, pending notifications, and delivered notifications without recording item content on the final Stage 10R build.

### Real-device lifecycle and safety

- [x] `R01` Initial authorized import completes for Canvas and SIweb; only aggregate read/new/update/cancel/skip counts and redacted status categories are recorded.
- [ ] `R02` A test create produces exactly one bound event on the Mac dedicated iCloud calendar and exactly one matching event on iPhone after iCloud convergence.
- [ ] `R03` Repeated sync preserves one Mac event, one iPhone event, and one notification per unique notification key; it creates no duplicate.
- [ ] `R04` An authorized source update changes the same bound event on Mac and iPhone; no delete-and-recreate duplicate remains.
- [ ] `R05` Authorized cancellation removes only that bound event on Mac and iPhone.
- [ ] `R06` The unrelated control calendar's aggregate item count and control item remain unchanged through create, repeat, update, cancellation, recovery, and cleanup checks.
- [ ] `R07` Calendar permission denial/revocation leaves sources and local views usable, preserves bindings, and touches no Calendar event; restoring permission safely catches up once.
- [ ] `R08` Notification permission denial/revocation leaves sync and Calendar usable; restoring permission reconciles pending notifications without duplicates.
- [x] `R09` A synthetic notification is pending once and delivered once within the recorded tolerance; disabling notifications blocks a further test notification.
- [ ] `R10` Offline recovery isolates the network failure, preserves existing data/events, explains the failure with a redacted category, and catches up safely after connectivity returns.
- [ ] `R11` Sleep/wake recovery triggers a compensating sync within five minutes while logged in, without duplicate side effects.
- [x] `R12` A failure of one source does not block the other; the failed source is explainable and catches up after recovery.
- [ ] `R13` A pending or rejected AI-derived inferred date creates zero Calendar events and zero deadline notifications. Only explicit confirmation may make it eligible.
- [ ] `R14` Apple Calendar cleanup preview includes only revalidated app-owned bindings; selected cleanup changes no unrelated calendar item.

### Seven-day and defect acceptance

- [ ] `T01` Seven consecutive local calendar days have a dated privacy-safe record below.
- [ ] `T02` During the trial there is no Calendar mis-deletion, unconfirmed inferred-date side effect, duplicate deadline notification, or duplicate managed event.
- [ ] `T03` Every discovered critical/high-severity Phase 1 defect is fixed with a focused regression test and the final complete suite passes.
- [ ] `T04` The final signed build and real-device lifecycle are rechecked after any acceptance-affecting fix.

## Evidence collection protocol

For each real-device observation, record local date/time and timezone, the scenario ID, device (`Mac`, `iPhone`, or both), expected aggregate result, observed aggregate result, convergence latency when relevant, and `PASS`/`FAIL`/`BLOCKED`. Evidence may be a privacy-safe result file, a redacted diagnostic export, or a human observation recorded in this handoff. Screenshots are optional and must exclude all private school content.

Use stable synthetic labels such as `Stage10-Control` and `Stage10-Lifecycle` only in private on-device test items. Do not copy those items' content into the handoff. Record counts, binding continuity, timestamps, and status categories only. For iCloud convergence, observe the same lifecycle item on both devices and record the elapsed time; do not claim instantaneous delivery.

Severity rules:

- `Critical`: unauthorized source write, credential/private-content leak, unrelated Calendar deletion/modification, or an unconfirmed inferred date reaching Calendar/notifications.
- `High`: duplicate managed event/notification, missed authorized cancellation, persistent cross-device divergence, failed source isolation, unsafe recovery, or a mandatory workflow that cannot complete on supported devices.
- `Medium/Low`: degraded presentation, delayed but safely convergent behavior beyond the target, or a non-safety usability issue with a documented workaround.

On a defect, stop the affected destructive/side-effect scenario, preserve privacy-safe diagnostics, identify the smallest Phase 1 repair, add a regression test, run the focused test and full suite, rebuild/re-sign, and repeat every affected real-device scenario. Do not implement unrelated refactors or Phase 2 behavior.

## Preflight evidence log

| ID | Local date/time (Asia/Macau) | Result | Privacy-safe evidence |
| --- | --- | --- | --- |
| P01 | 2026-09-04 21:09 CST | PASS | `./scripts/test.sh`: 143 tests / 12 suites passed; 0 failures. |
| P02 | 2026-09-04 21:10 CST | PASS | Signed app built and launched; packaged Keychain smoke, strict signature verification, plist lint, and sandbox/network/Calendar entitlement checks passed. |
| P03 | 2026-09-04 21:11 CST | PASS | Read-only Canvas smoke completed: 6 courses, 7 tasks, 7 announcements; output contained aggregate counts only. |
| P04 | 2026-09-04 21:13 CST | PASS | Initial probe failed closed with `loginRedirect`; signed-app interactive reauthorization stored the renewed session only in Keychain, then the read-only retry passed with 92 meetings and 0 cancelled. No credential/private content was exposed. |
| P05 | 2026-09-05 11:22 CST | PENDING | The pre-ST10-002 build passed: user selected the dedicated iCloud calendar, confirmed it on iPhone, and the app verified one iCloud managed identity. The final ST10-002 signature revoked Calendar permission again; identity is preserved but final-build restoration/reselection is pending. |
| P06 | 2026-09-05 22:28 CST | PASS | Final Stage 10R production Settings reports local notifications enabled and the notification master switch on. No test content or private notification body was recorded. |
| P07 | 2026-09-05 22:28 CST | PASS | Final Stage 10R production Settings reports automatic sync enabled at the 3,600-second target and the macOS Login Item state `enabled`; launch recovery started on the final build. |
| P08 | 2026-09-05 11:23 CST | PASS | Automated aggregate baseline: 0 managed bindings, 1 separate synthetic iCloud control calendar, 1 control event, 0 notification deliveries. Control identifiers remain only in the local app-container state file. |

P05-P08 must be revalidated against the final accepted Stage 10R signed build. The previously selected iCloud identity and control baseline may remain preserved, but no lifecycle or trial credit carries forward until the final build proves access, selection, notification state, background scheduling, and aggregate before-counts again.

## Stage 10R resume gate

The main project conversation accepted `.agent/handoffs/stage-10r.md` and resumed Stage 10 on 2026-09-05. The seven-day counter is reset to **0/7**. The final signed Stage 10R build, dedicated iCloud calendar and iPhone visibility, notification permission/master switch, background scheduler, real manual refresh, real background refresh, and affected device lifecycle must all be revalidated first. The setup/revalidation calendar date is never Day 1; only the following complete Asia/Macau natural day may begin the consecutive trial.

| Gate | Final Stage 10R evidence | Result |
| --- | --- | --- |
| Signed build identity/verification | 2026-09-05 22:27 CST: strict signature, plist lint, Launch Services launch, and packaged Keychain smoke passed | PASS |
| Real SQLite-backed Today/Schedule/Tasks/Announcements | 2026-09-05 22:28 CST: normal production launch showed the Stage 10R weekly Today UI with real database content and no preview selector, synthetic footer, or known fixture records | PASS |
| Dedicated iCloud calendar + iPhone visibility | pending user/device recheck | PENDING |
| Notification permission + master switch | 2026-09-05 22:28 CST: production UI reports enabled; master switch value is on | PASS |
| Background scheduler/Login Item | 2026-09-05 22:28 CST: production UI reports enabled at the 60-minute target with macOS item enabled | PASS |
| Real manual sync + committed UI reload | pending | PENDING |
| Real background sync + safe UI reload | 2026-09-05 22:21 CST launch recovery started but is awaiting the user's local macOS Keychain authorization for the final ad-hoc signature; sampling showed both source readers blocked in `SecItemCopyMatching`, with no new source run committed | BLOCKED / SAFE |

The pending Keychain authorization is an external final-signature acceptance action, not a source credential request. The user must approve the two existing app Keychain items locally; no password, token, session, URL, identifier, or source content may enter chat or evidence. Until approval, the scheduler truthfully remains `running`, creates no misleading completed source result, and receives no trial credit.

## Real-device evidence log

| Scenario | Local date/time (Asia/Macau) | Device | Expected aggregate | Observed aggregate / latency | Result |
| --- | --- | --- | --- | --- | --- |
| R01 initial import | 2026-09-04 21:29 CST | Mac | Both sources finish independently; baseline causes no notification storm | Canvas committed 20 read/20 inserted; SIweb committed 98 read/98 inserted; 12 courses, 92 meetings, 7 tasks, 7 announcements persisted; zero notification deliveries | PASS |
| R02 create | 2026-09-05 11:24 CST | Mac + iPhone | One managed event on each device | Mac/EventKit: exactly 1 after two identical create applications; independent control unchanged. iPhone human observation pending. | PENDING |
| R03 repeated sync | pending | Mac + iPhone | Counts remain one; no duplicate notification | pending | PENDING |
| R04 source update | pending | Mac + iPhone | Same binding/event updates on both devices | pending | PENDING |
| R05 authorized cancellation | pending | Mac + iPhone | Bound event disappears from both devices | pending | PENDING |
| R06 unrelated calendar isolation | pending | Mac + iPhone | Control item/count unchanged | pending | PENDING |
| R07 Calendar denial/recovery | 2026-09-05 11:10 CST | Mac + iPhone | No event touched while denied; one safe catch-up | Denial half observed: latest signed build reports permission revoked; managed identity retained; zero bindings/events created by the lifecycle tool, which failed closed as `dedicated_calendar_invalid`. User restoration and catch-up remain pending. | PENDING |
| R08 Notification denial/recovery | pending | Mac | Other subsystems usable; one reconciled schedule | pending | PENDING |
| R09 notification timing | 2026-09-04 21:16 CST | Mac | Pending once, delivered once in tolerance, disabled blocks | Scheduled for 3s; observed pending once and delivered once within the 6s observation period; disabled follow-up was blocked | PASS |
| R10 offline/recovery | pending | Mac + iPhone | Explainable offline state; preserved state; safe catch-up | pending | PENDING |
| R11 sleep/wake recovery | pending | Mac + iPhone | Compensating sync within 5 minutes; no duplicates | pending | PENDING |
| R12 source failure isolation | 2026-09-04 21:11-21:29 CST | Mac | Healthy source completes; failed source recovers safely | Parallel probes: Canvas passed while SIweb failed closed as `loginRedirect`; SIweb reauthorization/retry passed; production catch-up then committed both sources independently | PASS |
| R13 AI confirmation gate | pending | Mac | Zero Calendar/deadline side effects before confirmation | pending | PENDING |
| R14 Calendar cleanup | pending | Mac + iPhone | Only previewed owned event changes; control unchanged | pending | PENDING |

## Seven-day operational log

The trial counter is **0/7** after Stage 10R acceptance. The planned window is seven consecutive local dates beginning only after the final signed Stage 10R build has revalidated its real database-backed UI, manual/background refresh, `P01`-`P08`, and the affected real-device lifecycle. The calendar day containing that setup/revalidation is not Day 1; only the next complete natural day may be counted. Shift all seven rows together if any prerequisite remains incomplete.

| Trial day | Local date (Asia/Macau) | Online/awake observation window | Canvas status/counts | SIweb status/counts | Calendar Mac/iPhone duplicate & control check | Notification duplicate/timing check | Recovery or permission exercise | Defects | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 2 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 3 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 4 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 5 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 6 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |
| 7 | TBD | pending | pending | pending | pending | pending | pending | none recorded | PENDING |

Each daily row must include a dated observation rather than merely an automated process run. Aggregate counts may be expressed as `read/new/update/cancel/skip`; source errors must use fixed redacted categories. `No duplicates` means both the managed-event count and relevant notification unique-key count were checked. `Control unchanged` means the unrelated calendar item was still present and unmodified.

## Defect log and regression evidence

| Defect | Severity | First observed | Privacy-safe symptom | Fix / changed files | Focused regression | Full-suite result | Real-device recheck | State |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ST10-001 opaque Keychain source failure category | High | 2026-09-04 | Production history collapsed Keychain access failures to `unknown`, preventing actionable explanation | `SyncEngine.swift`: map `SecretStoreError` to fixed `unauthorized`; `SyncEngineTests.swift`: regression | `./scripts/test.sh --filter keychainFailureClassification`: 1/1 PASS | `./scripts/test.sh`: 144/144 PASS | Signed-app production restart and real source catch-up passed; explicit permission-denial recheck remains under R07/R08 | FIXED, REAL DENIAL RECHECK PENDING |
| ST10-002 production UI read synthetic fixtures | High | 2026-09-05 | Real Canvas/SIweb rows were committed to SQLite while all primary pages still rendered fixture snapshots; refresh did not run or reload the real pipeline, and due-today used a fixed fixture date | Added `DashboardDataReading`/`SQLiteDashboardDataReader`; injected it through `AppEnvironment`; production startup/manual/background paths now reload committed data; queued manual refresh waits behind an active run; production preview/synthetic controls are isolated; current local calendar/time drives date grouping; stable row IDs retain local-only state. Updated app/features/background/model and README. | `./scripts/test.sh --filter Stage10DashboardDataTests`: 8/8 PASS; targeted DashboardModel 9/9, Persistence 12/12, NotificationBackground 17/17 PASS | Final `./scripts/test.sh`: 152 tests / 13 suites PASS, 0 failures | Final signed production UI: all four primary pages rendered database-backed content, local date was current, and no Preview state, synthetic footer, or known fixture records appeared. Final manual/background live refresh and permission-dependent lifecycle recheck remain pending. | CODE FIXED; FINAL LIVE REFRESH/PERMISSION RECHECK PENDING |

## Stage 10 phased Calendar lifecycle harness

The signed app now exposes a privacy-safe Stage 10-only acceptance command with `baseline`, `create`, `update`, `cancel`, and deferred `cleanup` phases. Baseline creates a separate synthetic control calendar/event in the same iCloud source and stores its identifiers only in a local app-container state file. It never selects or reads a personal calendar. Every lifecycle phase verifies the control event is unchanged. The lifecycle itself uses one fully synthetic task in the production Calendar boundary and refuses to run unless the persisted dedicated calendar is valid and its source kind is iCloud. Create and update are replayed twice and must still resolve to one owned event; update must preserve the EventKit external identity; cancel is replayed twice and removes the synthetic local seed after the bound event is gone. Cleanup removes only the locally recorded control calendar after trial acceptance. Output contains only fixed aggregate fields and failure categories.

The phases are intentionally separate so the user can confirm Mac/iPhone convergence between them. No phase searches a personal calendar by title, outputs an EventKit identifier, or records school content. On the pre-ST10-002 build, baseline and create passed on Mac, including repeated-create idempotency and control isolation; iPhone observation was not completed. The final ST10-002 build must revalidate permission and repeat the acceptance-affecting lifecycle before those results can satisfy T04.

## Commands and results

```sh
./scripts/test.sh
# PASS: 143 tests / 12 suites in 0.411s; 0 failed (2.26s wall including build/startup).

./scripts/build-app.sh
# PASS: signed dist/Campus Dashboard.app produced (0.77s wall).

./scripts/verify-app.sh
# PASS: Launch Services launch and packaged Keychain create/read/delete smoke (0.62s wall).

codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS.

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: both files valid. Info.plist contains the full Calendar access usage description.

codesign -d --entitlements - "dist/Campus Dashboard.app"
# PASS: app-sandbox, network-client, and Calendar entitlements present.

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --canvas-smoke-test
# PASS: read-only aggregate result: 6 courses, 7 tasks, 7 announcements.

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-smoke-test
# Initial result: redacted `loginRedirect`; saved authorized session expired.

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-authenticate
# PASS: signed-app non-persistent authorization completed; session saved only to Keychain.

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-smoke-test
# PASS after recovery: read-only aggregate result: 92 meetings, 0 cancelled.

open -n -W "dist/Campus Dashboard.app" --args --calendar-smoke-test <sandbox-container-result-path>
# PASS on an iCloud EventKit source: create=1, update=1, cancel=1, repeated_sync=1,
# external_recovery=1, isolated_calendar=1. The temporary test calendar was removed.
# This proves Mac-side production EventKit behavior but not iPhone observation.

open -n -W "dist/Campus Dashboard.app" --args --notification-smoke-test <sandbox-container-result-path>
# PASS: permission=authorized, pending=1, delivered=1, disabled_blocks=1.

open -n -W "dist/Campus Dashboard.app" --args --background-smoke-test <sandbox-container-result-path>
# PASS: login_item=enabled, short_interval=1, disabled_count=1, recovery_count=2,
# final=disabled. This isolated probe does not establish that production automatic sync is enabled.

./scripts/test.sh --filter keychainFailureClassification
# PASS after ST10-001: 1 test / 1 suite.

./scripts/test.sh
# PASS after ST10-001: 144 tests / 12 suites; 0 failed.

./scripts/build-app.sh && ./scripts/verify-app.sh
# PASS after ST10-001: signed app rebuilt, launched, and packaged Keychain smoke passed.

# Privacy-safe read-only SQLite aggregate queries against the app container database.
# PASS: production launch recovery committed Canvas 20 read/20 inserted and SIweb
# 98 read/98 inserted; baseline persisted 12 courses, 92 meetings, 7 tasks, and
# 7 announcements with zero notification deliveries. Background state reports
# enabled, 3,600-second target, successful launch recovery, and no error category.
# Calendar is not configured yet: zero managed identity/bindings and 80 pending
# outbox items safely retained with `delivery_failed` rather than touching a calendar.

./scripts/test.sh --filter CalendarIntegrationTests
# PASS after adding the phased Stage 10 harness: 15 tests / 1 suite.

./scripts/test.sh
# PASS after adding the phased Stage 10 harness: 144 tests / 12 suites; 0 failed.

./scripts/build-app.sh
# PASS: signed app rebuilt with the Stage 10 lifecycle command.

open -n -W "dist/Campus Dashboard.app" --args \
  --stage10-calendar-lifecycle create <sandbox-container-result-path>
# BLOCKED/SAFE: `icloud_calendar_not_configured`; no event was created.

open -n -W "dist/Campus Dashboard.app" --args \
  --stage10-calendar-lifecycle baseline <sandbox-container-result-path>
# First attempt after rebuild: BLOCKED/SAFE `dedicated_calendar_invalid`; no event created.
# After user restored Calendar access: PASS source=icloud, managed_bindings=0,
# control_calendars=1, control_events=1, notifications=0.

open -n -W "dist/Campus Dashboard.app" --args \
  --stage10-calendar-lifecycle create <sandbox-container-result-path>
# PASS: source=icloud, managed_events=1, repeated_sync=1, control_unchanged=1.

./scripts/test.sh --filter Stage10DashboardDataTests
# PASS after ST10-002: 8 tests / 1 suite. Covers seeded SQLite mapping, restart,
# manual add/update/cancel reload, background completion reload, queued manual
# refresh, empty/configuration-failure states, fixture exclusion, and local-date logic.

./scripts/test.sh --filter DashboardModelTests
# PASS after ST10-002: 9/9.

./scripts/test.sh --filter PersistenceTests
# PASS after ST10-002: 12/12.

./scripts/test.sh --filter NotificationBackgroundTests
# PASS after ST10-002: 17/17.

./scripts/test.sh
# FINAL PASS after the queued-manual concurrency repair: 152 tests / 13 suites,
# 0 failures in 0.442s (0.84s wall).

./scripts/build-app.sh
# FINAL PASS after ST10-002: signed app produced (11.97s build; 12.30s wall).

./scripts/verify-app.sh
# FINAL PASS: Launch Services and packaged Keychain smoke (0.60s wall).

codesign --verify --deep --strict "dist/Campus Dashboard.app"
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# FINAL PASS: strict signature and both property lists valid.

# Real signed production UI inspection, recording booleans/counts only.
# PASS: Today uses 2026-09-05 Asia/Macau local date; Today, Schedule, Tasks, and
# Announcements all render database-backed nonempty content; Preview state,
# synthetic footer/text, and known fixture records are absent on every page.
# Settings truthfully reports the final signature's revoked Calendar permission
# and disabled notification master switch; it does not fall back to fake data.

# Stage 10 resume after accepted Stage 10R repair:
codesign --verify --deep --strict "dist/Campus Dashboard.app"
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
./scripts/verify-app.sh
# PASS on 2026-09-05 22:27 CST: strict signature, both plists, Launch Services
# launch, and packaged Keychain create/read/delete smoke. Log retained under
# /tmp/campus-stage10-resume.uUd54r.

# Normal final Stage 10R production launch, aggregate/boolean UI inspection only.
# PASS: weekly Monday-Sunday Today presentation and week navigation are present;
# real SQLite content is nonempty; announcement sidebar is present; no preview
# selector, synthetic footer, or known fixture record appears. Notification access
# and master switch are enabled. Automatic sync and its macOS Login Item report
# enabled at the 3,600-second target. Calendar access is revoked and awaits the
# user's system authorization/reselection before lifecycle work can resume.

! rg -n '<credential/private-key patterns>' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
# PASS: no credential/private-key pattern found.

! rg -n '[[:blank:]]+$' Sources/CampusDashboard/Sync/SyncEngine.swift \
  Tests/CampusDashboardTests/SyncEngineTests.swift .agent/handoffs/stage-10.md
# PASS: no trailing whitespace in Stage 10 changed paths.
```

Successful verbose logs are retained in the unique temporary directory named in `/tmp/campus-stage10-logdir` for this active acceptance session. Privacy-safe smoke result files are in the app sandbox container. The SIweb fail-closed/recovery sequence is preserved because it affects live-source acceptance.

The Codex heartbeat `Campus Dashboard Stage 10 daily acceptance` is active daily at 20:00 Asia/Macau and continues this same task/evidence file. It must be paused after Stage 10 genuinely reaches `PASS`.

## Changed files

- `.agent/handoffs/stage-10.md` (new Stage 10 checklist and evidence log)
- `Sources/CampusDashboard/Sync/SyncEngine.swift` (ST10-001 actionable Keychain failure classification)
- `Tests/CampusDashboardTests/SyncEngineTests.swift` (ST10-001 regression)
- `Sources/CampusDashboard/Calendar/Stage10CalendarAcceptanceTool.swift` (new phased, aggregate-only real-device lifecycle harness)
- `Sources/CampusDashboard/App/CampusDashboardApp.swift` (dispatches the Stage 10 lifecycle phases)
- `Sources/CampusDashboard/App/DashboardDataService.swift` (ST10-002 database-to-snapshot read boundary)
- `Sources/CampusDashboard/App/AppEnvironment.swift` (injects the production database reader)
- `Sources/CampusDashboard/App/DashboardModel.swift` (real startup/manual/background reload and local-date behavior)
- `Sources/CampusDashboard/Background/BackgroundSyncScheduler.swift` (manual run and completion reload boundary; queued manual waits behind an active run)
- `Sources/CampusDashboard/Features/Today/TodayView.swift` (real current-date/content states)
- `Sources/CampusDashboard/Features/Schedule/ScheduleView.swift` (real empty/content states)
- `Sources/CampusDashboard/Features/Tasks/TasksView.swift` (real empty/content states)
- `Sources/CampusDashboard/Features/Announcements/AnnouncementsView.swift` (real empty/content states)
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift` (production-aware confirmation state)
- `Tests/CampusDashboardTests/Stage10DashboardDataTests.swift` (ST10-002 end-to-end data/reload regressions)
- `Tests/CampusDashboardTests/DashboardModelTests.swift` (explicit fixture preview tests)
- `Tests/CampusDashboardTests/PersistenceTests.swift` (explicit fixture setup where intended)
- `Tests/CampusDashboardTests/NotificationBackgroundTests.swift` (explicit fixture setup where intended)
- `README.md` (production database-backed UI and refresh behavior)

No central contract, roadmap, status file, stage prompt, project specification, or another stage handoff was edited.

## Current blockers and conclusion

Stage 10R is accepted and its final signed production UI has passed the initial Stage 10 resume check: it renders the weekly calendar presentation from real committed data without fixture fallback, notifications are enabled, and automatic sync/Login Item report enabled. The final signature still needs two user-local recoveries: macOS is awaiting Keychain authorization for both existing source items, leaving launch recovery safely in progress without a committed source result, and Calendar access is revoked. The user must approve Keychain access locally, restore Calendar access in Settings, reselect the preserved dedicated iCloud calendar, and confirm it remains visible on iPhone. Real manual/background refresh, the affected cross-device lifecycle, permission recovery, offline/sleep recovery, AI-side-effect gating, cleanup isolation, and seven consecutive elapsed-day observations remain incomplete. The seven-day counter is reset to **0/7**, and the setup/revalidation day cannot count as Day 1. Stage 10 is therefore `PARTIAL` and must not be accepted. A `PASS` conclusion is prohibited until the full evidence matrix, all seven dated daily rows, and defect/regression requirements are complete.
