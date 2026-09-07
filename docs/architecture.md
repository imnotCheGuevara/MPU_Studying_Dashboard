# Campus Dashboard architecture

## Stage 02 boundaries

The application remains local-only. SwiftUI depends on source-independent domain types and a `LocalStateRepository`. The production repository uses SQLite in the app's user Application Support container; tests can inject in-memory or temporary-file repositories. A repository failure is surfaced to `DashboardModel.persistenceError` and never changes an official source field.

```text
SwiftUI / DashboardModel
        │
        ├── LocalStateRepository ── SQLitePersistenceRepository ── SQLite
        └── domain models

future orchestration boundaries (fake only in Stage 02)
        ├── CanvasService / SIwebService
        ├── SyncService
        ├── CalendarService / NotificationService
        ├── AIService
        └── Clock / IDGenerator

credential boundary
        └── SecretStore ── KeychainSecretStore ── macOS Security framework
```

No external service protocol has a live implementation in Stage 02. Canvas and SIweb payload contracts are read-only value types. Calendar and notification contracts accept commands but their fakes do not call system frameworks. AI receives a deliberately minimal request type and its fake is a no-op suggestion.

## Transactions and migrations

`SQLiteDatabase` serializes access, enables foreign keys, uses WAL journaling, and exposes an immediate transaction. `DatabaseMigrator` reads `PRAGMA user_version` and applies every missing migration in a transaction. Schema version 1 is the Stage 02 baseline. A database newer than the executable is rejected instead of guessed or downgraded.

Future schema changes add a new ordered migration and advance `currentSchemaVersion`. Migrations must be covered both from an empty database and from the immediately preceding checked-in schema fixture.

## Application identity and signing

`scripts/build-app.sh` builds the release executable, creates a conventional `.app`, installs the checked-in `Info.plist`, and signs with the checked-in entitlements. The Bundle ID is permanently based at `com.campusdashboard.desktop`. The current ad-hoc signature is deterministic and suitable for local validation, including Keychain access from the bundle.

Adopting Xcode and Apple signing later must preserve the Bundle ID and replace ad-hoc signing with one stable team identity. The entitlement baseline enables App Sandbox and outbound client networking because later read-only connectors require it. New capabilities, access groups, usage descriptions, login items, hardened runtime, and notarization must be added only in their owning stages and verified with the final signing identity.

## Secret handling

`SecretStore` accepts opaque `Data`. `KeychainSecretStore` stores generic-password items scoped by service and account. It maps denial, unavailable/missing-entitlement, missing-item, invalid-data, and other status cases into caller-visible errors. Tests use `FakeSecretStore` or an injected Keychain client; ordinary automated tests never depend on the user's Keychain.

Secret values are never written to SQLite, configuration, fixtures, logs, smoke-test output, or handoffs. Clearing a secret is independent from clearing local database categories.
