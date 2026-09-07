# Stage 09 handoff

Status: PASS

## Implemented scope

- Added Stage 09 end-to-end fake-service scenarios covering first synchronization, deterministic incremental updates, independent Canvas/SIweb failure, offline preservation and recovery, cancellation, durable Calendar/Notification outbox retry, and persisted-state recovery after reopening the database.
- Re-ran the Stage 08 AI integration suite covering confirmation, correction, rejection, undo, awaited notification reconciliation, Calendar desired-state reconciliation, and restart recovery.
- Added database-backed Canvas/SIweb health presentation. Errors are mapped to fixed redacted categories with specific recovery guidance for authorization, permission, offline, rate limit, changed response, temporary service failure, cancellation, and unknown failure.
- Added categorized clearing for source cache, local user state, sync history, AI history, and completed notification history. Each category is independently confirmed. Source-cache clearing discards pending side-effect intents and reconciles obsolete local reminders, but none invokes Keychain or Calendar deletion.
- Added a separate credential-clearing action for the Canvas token and authorized SIweb session. It calls only the corresponding macOS Keychain stores and retains every SQLite category and Calendar event.
- Added a separate Apple Calendar cleanup flow. Preview includes only active bindings whose dedicated calendar, source, deterministic ownership marker, and current event all revalidate. Execution accepts only previewed binding IDs and repeats validation immediately before deletion. Ordinary cache clearing retains Calendar identity/bindings and does not touch EventKit.
- Added a viewable/exportable diagnostic JSON format based on an allowlist. It contains schema/format versions, time, fixed source/subsystem status categories and recovery guidance, and aggregate counts. It never queries or serializes source URLs, display names, raw payloads, content/title fields, account/object/event/notification identifiers, arbitrary diagnostic text, authorization headers, cookies, session material, or Keychain.
- Moved diagnostic generation, category clearing, credential clearing, and export work off the main actor. Added a 5,000-run responsiveness regression.
- Added Settings privacy/diagnostic controls, explicit destructive confirmation dialogs, stable accessibility labels/identifiers, live source status on Today and Settings, Command-R refresh, Command-comma Settings navigation, and Shift-Command-D diagnostic refresh.
- Documented the privacy boundary, clearing matrix, Calendar cleanup validation, diagnostic schema, keyboard controls, and verification commands.

## Changed files

- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsModels.swift` (new)
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift` (new)
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/Calendar/CalendarPersistence.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Features/Today/TodayView.swift`
- `Tests/CampusDashboardTests/IntegrationHardeningTests.swift` (new)
- `Tests/CampusDashboardTests/PrivacyDiagnosticsTests.swift` (new)
- `Tests/CampusDashboardTests/CalendarIntegrationTests.swift`
- `README.md`
- `docs/privacy-security.md` (new)
- `.agent/handoffs/stage-09.md` (new)

No central contract, roadmap, status file, stage prompt, project specification, or another stage handoff was edited. The repository was already entirely untracked at task entry; no reset, checkout, deletion, or cleanup of pre-existing files was performed.

## Verification commands and concise results

```sh
./scripts/test.sh --filter IntegrationHardeningTests
# PASS: 3 tests / 1 suite.

./scripts/test.sh --filter PrivacyDiagnosticsTests
# PASS: 5 tests / 1 suite; 5,000-run diagnostic case completed in 0.025s.

./scripts/test.sh --filter CalendarIntegrationTests
# PASS: 15 tests / 1 suite, including separate previewed cleanup and foreign-event isolation.

./scripts/test.sh --filter AIParsingTests
# PASS: 22 tests / 1 suite; confirm/correct/reject/undo, restart, Calendar and Notification convergence.

./scripts/test.sh --filter NotificationBackgroundTests
# PASS: 17 tests / 1 suite; denial/revocation, recovery, offline compensation, persisted scheduling.

./scripts/test.sh --filter DashboardModelTests
# PASS: 9 tests / 1 suite.

./scripts/test.sh
# PASS: final rerun after the queued-intent safety repair; 143 tests / 12 suites in 0.369s.

swift package clean
swift build --jobs 1
# PASS: clean debug build completed in 37.91s.

./scripts/build-app.sh
# PASS: final release build completed in 12.46s and produced the signed app.

./scripts/verify-app.sh
# PASS: launched through Launch Services and completed packaged Keychain create/read/delete smoke.

/usr/bin/time -p ./scripts/verify-app.sh
# PASS: real 0.17s, user 0.02s, sys 0.02s.

codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS.

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: both files valid.

codesign -d --entitlements - "dist/Campus Dashboard.app"
# PASS: signed app contains app-sandbox, network-client, and Calendar entitlements.

! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
# PASS: no credential/private-key pattern found.

! rg -n 'instance_url|display_name|source_url|payload|event_identifier|external_event_identifier|notification_key|system_notification_id|title|summary' Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift
# PASS: exporter implementation does not query sensitive/content-bearing columns.

! rg -n '[[:blank:]]+$' <all Stage-09 changed paths>
git diff --check
# PASS: whitespace/diff checks clean.

! rg -n 'iPhone.*(PASS|passed)|seven.day.*(PASS|passed)|7.day.*(PASS|passed)|Phase 2|study planning' Sources/CampusDashboard/Privacy Tests/CampusDashboardTests/IntegrationHardeningTests.swift Tests/CampusDashboardTests/PrivacyDiagnosticsTests.swift docs/privacy-security.md
# PASS: no Stage 10 or Phase 2 claim/scope.
```

## Automated-test totals

- Final complete suite: **143 tests in 12 suites, 143 passed, 0 failed**.
- Stage 09 additions: 3 end-to-end integration tests, 5 privacy/diagnostic tests, and 1 Calendar cleanup regression (9 tests total).
- Existing acceptance coverage retained: 22 AI, 17 Notification/background, 15 Calendar, and all Canvas, SIweb, sync-engine, persistence, secret-store, service-contract, and Dashboard model tests passed in the final suite.

## Manual/UI verification evidence

The final signed local app was launched through its bundle identity with synthetic/empty local data. No school service, external AI, Calendar write, notification scheduling, or credential entry was used.

- PASS: Today displayed independent Canvas and SIweb `not_configured` states with the actionable instruction to configure each source, while all local dashboard cards remained usable.
- PASS: Command-comma moved from Today to Settings.
- PASS: Settings' accessibility tree exposed named controls for every local-data category, separate Keychain credential clearing, separate Calendar cleanup preview, redacted diagnostic refresh/export, Calendar/Notification controls, AI, and background scheduling.
- PASS: Shift-Command-D refreshed the expanded diagnostic preview; the generated timestamp changed from `12:44:46Z` to `12:45:06Z` without blocking navigation.
- PASS: expanded diagnostic JSON showed only aggregate counts, schema/format version, source categories/actions, and subsystem categories/actions.
- PASS: selecting `Clear Source cache` opened a confirmation sheet explicitly stating that credentials and Apple Calendar events are retained. The action was cancelled; no data was changed.
- PASS: toolbar Refresh had an accessibility label; source-status cards were combined/labeled; privacy status and diagnostic preview exposed stable accessibility identifiers; cleanup controls had explicit action labels.
- PASS: the signed bundle launched and completed its independent Keychain smoke after the UI check.

## Privacy and credential-scan evidence

- Adversarial diagnostic tests placed synthetic secret/session markers, a credential-shaped authorization value assembled only at runtime, a private URL, a private title, and hostile subsystem strings in storage/input. None appeared in encoded diagnostic output.
- Unknown source names are omitted; unknown subsystem names are omitted; unknown subsystem states become the fixed `unavailable` category. Arbitrary recovery strings supplied to the exporter are replaced with fixed guidance.
- Category-clear tests run each of the five categories independently and prove the Keychain fake value, managed Calendar identity, and Calendar binding remain.
- Credential-clear tests prove both Keychain items are removed while the cached task and Calendar binding remain.
- Calendar cleanup test clears source cache first, proves both dedicated and personal Calendar events remain, previews only the valid app-owned event, deletes that event after revalidation, and proves the personal event plus deliberately foreign binding remain unchanged.
- Whole-tree credential/private-key pattern scan passed. No real credential, session, school content, URL, authorization header, diagnostic payload, or system identifier was recorded in tests, logs, UI evidence, or this handoff.

## Performance and responsiveness evidence

- Diagnostic export over 5,001 persisted sync-run rows completed in 0.025s in the focused test, below the explicit 2s regression ceiling.
- Privacy/diagnostic database and file operations execute in detached tasks rather than on the SwiftUI main actor.
- End-to-end fake-service lifecycle completed in 0.017s focused and 0.172s under the concurrent full suite.
- Signed-app launch plus packaged Keychain smoke completed in 0.17s wall time.
- Manual keyboard navigation and diagnostic refresh remained immediately responsive.

## Compatibility fixes to earlier components

- Stage 06 Calendar persistence gained a read-only active-binding query. `CampusCalendarService` gained preview and selected-cleanup methods so Stage 09 can reuse the exact existing identity/marker/external-ID validation rather than weakening or duplicating Calendar ownership rules.
- Stage 01 application shell/model/settings/today integration points now receive Stage 09 health/privacy dependencies, display production persisted status, and expose keyboard/accessibility controls. Existing fixture pages and local-state behavior remain intact.
- `AppEnvironment` constructs the Stage 09 service with the existing Stage 03 Canvas and Stage 04 SIweb Keychain service/account identities. No secret storage location or connector authorization behavior changed.
- No schema migration was needed; the implementation uses the accepted schema v7 tables and preserves earlier migrations.

## Remaining risks for Stage 10 real-device testing

- Verify the previewed cleanup list and selected deletion against the user's real dedicated EventKit calendar after a fresh signed build, including an intentionally unrelated same-name/personal event. Stage 09 fake EventKit coverage passes, but no real event was deleted in this stage.
- Exercise real macOS Calendar and Notification permission denial, revocation in System Settings, restoration, and queued-work recovery with the final signing identity. Automated permission lifecycle and isolation tests pass; this stage did not mutate the user's OS privacy settings.
- Verify iCloud propagation to a real iPhone for create, update, cancellation, retry, and cleanup. No iPhone/iCloud acceptance is claimed here.
- Run and document the required seven-day real-service trial, including sleep/offline recovery, Canvas/SIweb independent outages, background/login-item behavior, duplicate checks, and notification delivery. No seven-day acceptance is claimed here.
- Real external AI remains intentionally unavailable; any future provider still requires the accepted disclosure/field/retention/consent boundary. This is not a blocker for Phase 1 deterministic operation.

## Conclusion

All mandatory Stage 09 automated, build, signing, plist/entitlement, privacy/security scan, manual UI/accessibility, and responsiveness items were performed and passed. Stage 09 is `PASS`. Only the main project conversation may inspect and accept this handoff or authorize Stage 10.
