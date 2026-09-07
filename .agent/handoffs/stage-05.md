# Stage 05 handoff

Status: PASS

## Scope delivered

- Added a source-independent `DeterministicSyncEngine` with independent Canvas and SIweb readers, per-source `SyncRun` records, concurrent all-source orchestration with isolated results, and an actor-backed single-flight gate per source.
- Added deterministic Canvas and SIweb boundary mapping into unified courses, meetings, learning tasks, and announcements. Connector boundary payloads are retained as minimal raw records before unified-model writes; connector DTOs do not enter the domain model and no AI is involved.
- Added transactional application of raw records, unified records, field-level `ChangeRecord` rows, presence evidence, successful run state, source success state, and durable calendar/notification outbox work. An injected pre-commit failure test proves all of these writes roll back together.
- Added schema migration version 2 and the `source_presence` table for durable, per-account/object consecutive-complete-snapshot absence evidence. Version 1 upgrade and fresh migration are both tested.
- Added schema migration version 3 and the `source_baselines` table. Baseline completion is persisted conservatively by `(source_account_id, object_type)` and only inside a successfully committed complete-snapshot transaction. Existing v2 databases intentionally begin with no guessed baseline-completion rows.
- Added composite-source-identity idempotency, stable raw-content hashes, versioned outbox deduplication keys, persistent delivery attempts, bounded retry delay, and recovery of outbox rows left in `processing` by a crash.
- Added update handling for title, official/normalized type, official due time, course fields, meeting time, location, and source state. Updates preserve the unified object ID and record only changed fields.
- Added deletion safety: explicit source cancellation is immediate and soft; incomplete pages, failed requests, and a first complete-snapshot absence do not cancel an object; a second consecutive successful complete-snapshot absence soft-cancels it and emits downstream cancellation intents. Reappearance resets absence evidence and source state through the ordinary upsert path.
- Added cancellation checks before persistence and throughout transaction application. A cancelled fetch records only a category-level cancelled run and commits no source data.
- Added first-sync baseline behavior: historical tasks/announcements do not emit “new item” notification work, and already expired tasks/meetings do not emit calendar work. An incomplete initial task or announcement snapshot leaves that family suppressed; its first later complete snapshot establishes the durable baseline without notifying historical items. New items after that family baseline emit one durable notification intent.
- Made timestamp-free announcements idempotent. When both source publication and update timestamps are absent, the first local fallback is persisted once and reused on unchanged syncs, including after database restart.
- Calendar and notification execution remains behind the existing fake service contracts. No EventKit, UserNotifications, background scheduling, or AI implementation was added.

## Changed files

- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Sync/SyncModels.swift`
- `Sources/CampusDashboard/Sync/SyncSourceReaders.swift`
- `Sources/CampusDashboard/Sync/SyncEngine.swift`
- `Sources/CampusDashboard/Sync/OutboxProcessor.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/SyncEngineTests.swift`
- `.agent/handoffs/stage-05.md`

No project constraint, roadmap, status, stage prompt, project specification, or earlier-stage handoff was edited.

## Acceptance evidence

| Acceptance item | Evidence/result |
| --- | --- |
| Independent source runs and failure isolation | PASS — the all-source test runs Canvas and SIweb independently; an unauthorized Canvas result does not block or corrupt the successful SIweb transaction. |
| Canvas/SIweb deterministic unified mapping | PASS — connector-boundary tests map Canvas official quiz type/due date and SIweb course/meeting/timezone/location into normalized records without AI, while retaining minimal raw boundary records. |
| Transactional persistence | PASS — an injected failure immediately before commit leaves courses, tasks, raw records, change records, successful runs, presence evidence, and outbox empty; a separate redacted failure run is recorded after rollback. |
| Idempotency | PASS — repeated identical synchronization keeps one domain object per composite identity, creates no new changes or outbox work, and stores one raw row per stable content hash. Twenty consecutive Stage 05 suite runs passed. |
| Update identity and change records | PASS — title, official type, normalized type, due time, meeting time, location, and status updates retain the original object ID and generate the expected field-level records. |
| Durable outbox and crash recovery | PASS — outbox work survives a simulated `processing` crash state and is recovered on the next processor run; a fake-adapter failure persists attempt/error/availability state and retries the same stable command identity successfully. |
| Single-flight and cancellation | PASS — a second active run for the same source receives `already_running`; explicit task cancellation yields category `cancelled`, no source model writes, and no leaked flight. |
| Incomplete/failure deletion safety | PASS — a connector-final page marked incomplete, an injected failed request, and one complete-snapshot absence never cancel the stored task or increment unsafe evidence. |
| Explicit and two-snapshot cancellation | PASS — explicit SIweb cancellation updates the same meeting immediately; two consecutive successful complete-snapshot absences soft-cancel a task while retaining its row and audit history. |
| First-sync baseline | PASS — baseline historical task/announcement imports create no notification work; expired baseline items create no calendar work; a task first seen after baseline creates exactly one notification intent. |
| Conservative per-family baseline repair | PASS — a regression runs an incomplete initial task/announcement snapshot, closes the database, reopens it for the first complete historical snapshot, and verifies zero new-item notifications. It verifies separate durable task/announcement baseline rows and then confirms genuinely new post-baseline objects notify after another restart. |
| Timestamp-free announcement repair | PASS — an announcement with both source timestamps absent is inserted after baseline, the database is closed and reopened with a later clock, and an unchanged repeat preserves the original local fallback while producing `updatedCount == 0`, no additional `ChangeRecord`, and no additional outbox row. |
| Retry classification and redaction | PASS — connector rate-limit errors map to retryable `rate_limited`; stored run diagnostics contain only the category and exclude the injected private marker. Authorization, offline, temporary server, structural, malformed, persistence, and cancellation categories are explicitly mapped. |
| Stage boundary | PASS — scans found no EventKit, UserNotifications, ServiceManagement/background scheduler, OpenAI, or Anthropic implementation. Calendar and notification calls in Stage 05 target fakes only. |

## Commands and results

```sh
swift package clean && swift build --jobs 1
# PASS: clean debug build completed in 31.80s after the repair.

./scripts/test.sh
# PASS: 78 tests in 7 suites; Stage 05 has 18 tests, persistence has 9 tests.

./scripts/test.sh --filter PersistenceTests
# PASS: 9 tests, including fresh v3 migration, v1 -> v3, and conservative v2 -> v3 upgrade.

./scripts/test.sh --filter SyncEngineTests
# PASS: 18 Stage 05 tests, including both cross-database-restart regressions.

for run_index in {1..20}; do
  ./scripts/test.sh --filter SyncEngineTests
done
# PASS: all 20 repair runs; each run executed all 18 Stage 05 tests.

./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS: release app built in 31.97s and signed; verify-app launched the macOS app and completed the packaged Keychain smoke test.

! rg -n '^import (EventKit|UserNotifications|ServiceManagement)|EKEventStore|UNUserNotificationCenter|SMAppService|OpenAI|Anthropic' Sources Tests
! rg -n 'httpMethod[[:space:]]*=[[:space:]]*"(POST|PUT|PATCH|DELETE)"|uploadTask|dataTask[[:space:]]*\([^)]*from:' Sources/CampusDashboard/Sync
! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '[[:blank:]]+$' Sources/CampusDashboard/Sync Tests/CampusDashboardTests/SyncEngineTests.swift Sources/CampusDashboard/Persistence/DatabaseMigrator.swift Sources/CampusDashboard/Persistence/SQLiteDatabase.swift Tests/CampusDashboardTests/PersistenceTests.swift
git diff --check
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: scope, read-only, credential, whitespace, plist, entitlement, and diff checks returned clean.
```

## Manual and integration checks

- The signed release app launched normally and completed the existing packaged-identity Keychain lifecycle smoke test.
- Stage 05 integration used deterministic synthetic Canvas/SIweb boundaries and fake calendar/notification adapters, as required. No live source response, credential, identifier, title, location, or personal content was captured.
- Stage 03 and Stage 04 already provide PASS evidence for the unchanged live read-only connector boundaries. Stage 05 adds no new source endpoint and therefore did not repeat credential-bearing live reads.
- The repaired baseline and announcement tests explicitly destroy and recreate the SQLite connection between runs; they do not rely on in-memory engine state.

## Remaining limitations

- The accepted Canvas and SIweb service contracts currently expose complete paginated snapshots rather than a persistent source delta cursor. Stage 05 propagates collection completeness and safely supports incomplete reads; no unsupported incremental capability is claimed.
- Outbox execution is exercised only through fake calendar and notification adapters. Real EventKit ownership/binding enforcement belongs to Stage 06; real notification delivery and background/hourly scheduling belong to Stage 07.
- An external side effect that succeeds immediately before a process crash can be offered again after recovery; downstream commands carry stable object/key identity and are required to be idempotent. Stage 06 and Stage 07 adapters must enforce that contract against their respective system APIs.
- No manual or background sync UI wiring was added in this stage. The engine exposes per-source and all-source orchestration for the later application/scheduler integration boundary.

## Handoff conclusion

All mandatory Stage 05 acceptance items were executed and passed. Stage 05 is marked `PASS`; only the main project conversation may inspect and accept it or authorize Stage 06/07.
