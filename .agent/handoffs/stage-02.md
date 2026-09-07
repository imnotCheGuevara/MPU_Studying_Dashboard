# Stage 02 handoff

Status: PASS

## Scope delivered

- Promoted the SwiftPM executable into a reproducibly generated `dist/Campus Dashboard.app` with stable Bundle ID `com.campusdashboard.desktop`, checked-in `Info.plist`, checked-in entitlement baseline, deterministic ad-hoc signing, signature verification, and Launch Services verification.
- Added a packaged-identity Keychain smoke mode that creates, reads, and deletes a generated opaque value. It writes only a non-sensitive PASS/failure category to the app's sandbox Application Support container.
- Added a serialized SQLite layer with foreign keys, WAL mode, immediate transactions, bound values, version checking, and atomic `PRAGMA user_version` migration.
- Added schema version 1 for all required Stage 02 entities: source accounts, raw records, courses, meetings, tasks, announcements, local user state, sync runs, change records, calendar bindings, notification deliveries, AI parse results, and durable outbox work.
- Added persistence repositories for source accounts, courses, learning tasks, local state, and durable outbox. Composite source constraints and outbox deduplication are enforced by SQLite, not by title or process memory.
- Wired task completion and announcement read state through `LocalStateRepository`. The packaged app uses its sandbox Application Support database and restores state after relaunch; storage initialization failures remain caller-visible via `DashboardModel.persistenceError`.
- Added `SecretStore`, a Security.framework-backed Keychain implementation, an in-memory fake, generated-data lifecycle behavior, and caller-visible denied/unavailable/not-found/invalid/status errors.
- Added testable contracts and deterministic fakes for Canvas, SIweb, sync, calendar, notifications, AI, clock, and ID generation. There are no live adapters or system side effects for these contracts in Stage 02.
- Documented the architecture, schema, migration strategy, Bundle ID, signing/entitlement baseline, Xcode adoption requirements, and secret-handling boundary.

## Changed files

- `Package.swift`
- `.gitignore`
- `README.md`
- `Resources/Info.plist`
- `Resources/CampusDashboard.entitlements`
- `scripts/build-app.sh`
- `scripts/verify-app.sh`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/Repositories.swift`
- `Sources/CampusDashboard/Security/SecretStore.swift`
- `Sources/CampusDashboard/Security/KeychainSmokeTest.swift`
- `Sources/CampusDashboard/Services/ServiceContracts.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/SecretStoreTests.swift`
- `Tests/CampusDashboardTests/ServiceContractTests.swift`
- `docs/architecture.md`
- `docs/data-model.md`
- `.agent/handoffs/stage-02.md`

No roadmap, status, project constraint, stage prompt, project specification, or earlier-stage handoff was edited.

## Acceptance evidence

| Acceptance item | Evidence/result |
| --- | --- |
| Clean build succeeds | PASS — `swift package clean` followed by `swift build --jobs 1` completed with `Build complete!` using Apple Swift 6.3.3. |
| All automated tests pass | PASS — `./scripts/test.sh` ran 23 tests in 4 suites; all passed. The 14 new tests cover schema creation/version safety, CRUD, composite uniqueness, official/suggested/local separation, durable restart/outbox behavior, app-model restart, Keychain lifecycle/error mapping, and fake service boundaries. |
| Required versioned schema and migrations exist | PASS — the empty-database test verified schema version 1, all 13 required tables, and enabled foreign keys. The version-safety test verified repeat migration is idempotent and schema version 99 is rejected rather than guessed/downgraded. |
| History survives process/repository recreation | PASS — the restart test closed the first database/repository scope, reopened the file with new instances, and recovered the source account and pending outbox. A separate model recreation test recovered a locally completed task. |
| Duplicate source objects upsert | PASS — two course writes with the same `(source_account_id, source_object_id)` but different local UUID/title resulted in one row, retained the original internal UUID/first-seen time, and updated the title. |
| Official, inferred/suggested, and local state are separate | PASS — the task test persisted official due time, a separate unconfirmed suggestion, and a separate `local_user_states` completion record without modifying either date. |
| Durable outbox persists and deduplicates | PASS — outbox work survived database recreation; enqueueing a second record with the same deduplication key returned the original record and kept one pending row. |
| Keychain implementation and safe errors | PASS — fake lifecycle and injected Security OSStatus tests verified denied and unavailable errors are explicitly visible. The real packaged-identity smoke test completed generated-value create/read/delete/not-found verification. No generated value was printed or written to its result. |
| Reproducible `.app`, stable identity, signing, and entitlements | PASS — `./scripts/build-app.sh` produced and verified an ad-hoc signed release app. `plutil` accepted both checked-in property lists; `defaults read ... CFBundleIdentifier` returned `com.campusdashboard.desktop`; extracted entitlements contained App Sandbox and outbound network client only. |
| Packaged app launches as an application | PASS — `./scripts/verify-app.sh` used `open -n -W` and returned `PASS com.campusdashboard.desktop`. A separate normal `open -n` check observed the `CampusDashboard` application process, AppleScript resolved application ID `com.campusdashboard.desktop`, and the app quit cleanly. |
| No embedded example credential | PASS — the repository-wide credential pattern scan (excluding generated `.build`, `dist`, and `.git`) returned no matches for token, bearer credential, assigned API key/client secret/password, access-key, or private-key patterns. |
| No future-stage implementation | PASS — source/test scan returned no EventKit, UserNotifications, ServiceManagement, URLSession, `EKEventStore`, or `UNUserNotificationCenter` usage. Canvas/SIweb/calendar/notification/AI types are protocols and fakes only. |
| Documentation updated | PASS — `README.md`, `docs/architecture.md`, and `docs/data-model.md` document packaging, identity/signing, migrations, repositories, service boundaries, Keychain, field separation, and every schema table. |

## Commands run

```sh
swift build --jobs 1
./scripts/test.sh
chmod +x scripts/build-app.sh scripts/verify-app.sh
./scripts/build-app.sh
./scripts/verify-app.sh

swift package clean
swift build --jobs 1
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh

open -n "dist/Campus Dashboard.app"
sleep 2
osascript -e 'tell application "System Events" to get exists process "CampusDashboard"'
osascript -e 'id of application "Campus Dashboard"'
osascript -e 'tell application id "com.campusdashboard.desktop" to quit'
sleep 1
! pgrep -f '/Campus Dashboard.app/Contents/MacOS/CampusDashboard'

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
defaults read "$PWD/dist/Campus Dashboard.app/Contents/Info" CFBundleIdentifier
codesign -d --entitlements - "dist/Campus Dashboard.app"
! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '^import (EventKit|UserNotifications|ServiceManagement)|URLSession|EKEventStore|UNUserNotificationCenter' Sources Tests
git diff --check
git status --short
swift --version
xcodebuild -version
sw_vers
```

## Manual and integration checks

- The final release app was launched normally through Launch Services. The process existed, resolved to the documented Bundle ID, remained active until asked to quit, and terminated cleanly.
- The packaged application itself exercised macOS Keychain using its bundle identity and sandbox entitlements. The generated test item was deleted before exit.
- The first packaging verification attempt wrote its non-sensitive result to a random host temporary directory. App Sandbox correctly prevented that cross-container write, so the verification could not find the result. The probe was changed to the bundle's sandbox Application Support directory and then passed repeatedly. No acceptance item remained skipped.
- The checked-in property lists were linted and the entitlements were inspected from the signed artifact, not only from source files.

## Remaining limitations and risks

- Full Xcode is not installed (`xcodebuild` reports Command Line Tools only). The current ad-hoc signature is intentionally a reproducible local-development identity, not an Apple Development/Developer ID distribution signature. Xcode adoption must preserve `com.campusdashboard.desktop`, choose one stable signing team, and add later capabilities/usage descriptions only in their owning stages.
- The entitlement baseline contains App Sandbox and outbound network client. EventKit usage descriptions, notification/background configuration, Service Management, hardened runtime, and notarization are intentionally not enabled or exercised in Stage 02.
- SQLite schema version 1 creates storage contracts for later entities, but Stage 02 repository operations focus on source accounts, courses, learning tasks, local state, and outbox—the records needed to prove identity, separation, and restart behavior. Later owning stages add focused repository operations without changing these identities.
- All visible source data remains synthetic. Canvas, SIweb, sync, calendar, notification, and AI implementations remain fakes; no real service or permission was contacted except macOS Keychain as explicitly required by this stage.
- The repository had no tracked baseline in this workspace (`git status` reports the project tree as untracked), so preservation was handled by editing only Stage 02-owned/new files and the narrowly required Stage 01 app/package/docs integration points.

## Required follow-up

- The main project conversation must inspect this handoff and actual worktree, re-run high-risk checks as appropriate, and explicitly accept Stage 02 before authorizing Stages 03 or 04.
