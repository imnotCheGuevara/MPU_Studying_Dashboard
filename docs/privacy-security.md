# Privacy, clearing, and diagnostics

Campus Dashboard is local-only. Canvas access authorization and the permitted SIweb session are generic-password items in macOS Keychain. They are never read by the privacy diagnostic exporter and are not stored in SQLite, UserDefaults, fixtures, screenshots, or logs.

## Separate destructive operations

Settings requires a separate confirmation for each operation:

| Operation | Removes | Explicitly retains |
| --- | --- | --- |
| Source cache | normalized courses, meetings, tasks, announcements, minimal raw records, presence/baseline cache, and pending side-effect intents | Keychain credentials, Calendar identity/bindings, and Apple Calendar events |
| Local completion/read state | local completion, read, hidden, and priority flags | source cache, credentials, and Calendar events |
| Sync history | sync runs and field-change history | source cache, credentials, and Calendar events |
| AI history | AI results, audit decisions, and applied-value history | deterministic source data, credentials, and Calendar events |
| Notification history | completed/non-scheduled delivery history | pending system reminders, credentials, and Calendar events |
| Credentials | Canvas and SIweb Keychain items | every SQLite category and every Calendar event |
| Apple Calendar cleanup | only explicitly previewed, revalidated app-owned events | every unbound, invalidly bound, other-calendar, and unrelated event |

Removing source cache intentionally retains Calendar bindings. Pending outbox intents are discarded so a queued Calendar mutation cannot execute after clearing; notification desired state is reconciled separately to cancel obsolete local reminders. This makes later Calendar cleanup possible without treating ordinary local-data clearing as permission to delete external events.

## Calendar cleanup safety

The preview requires full Calendar access and a currently valid dedicated-calendar identity. Each active binding must match the exact dedicated calendar identifier, source identifier, and deterministic ownership marker, and its current EventKit event must match those values. Invalid, ambiguous, missing, foreign-calendar, or marker-mismatched records are excluded. Execution accepts only binding IDs from the preview and performs the same validation again before deleting an event.

## Diagnostic export schema

Diagnostic JSON format version 1 contains:

- generation timestamp and database schema version;
- Canvas/SIweb status category, last successful time, fixed summary, and fixed recovery action;
- Calendar, Notifications, AI, background, and database status categories with fixed recovery guidance;
- aggregate row counts for operational tables.

The exporter does not serialize arbitrary error strings. It never queries source URLs, display names, content fields, raw payloads, binding/event identifiers, notification identifiers, or Keychain. Unknown source/subsystem names and status values are omitted or converted to a fixed unavailable category.

## Verification commands

```sh
./scripts/test.sh --filter IntegrationHardeningTests
./scripts/test.sh --filter PrivacyDiagnosticsTests
./scripts/test.sh --filter CalendarIntegrationTests
./scripts/test.sh --filter AIParsingTests
./scripts/test.sh --filter NotificationBackgroundTests
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
codesign --verify --deep --strict "dist/Campus Dashboard.app"
```
