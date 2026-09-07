# Stage 15R handoff — release readiness and validation closure

Status: `PARTIAL`

## Outcome

The release-candidate implementation, including the 2026-09-07 Canvas/SIweb reconciliation repair, is complete and the automated, privacy, packaging, and signature gates pass. The remaining acceptance gap is the main conversation's real bilingual UI and existing-dedicated-calendar walkthrough. This handoff therefore remains `PARTIAL` and does not start the seven-day trial.

No Outlook setup, authorization callback, token lookup, metadata probe, or background traffic is reachable from the production app in this release. The older Stage 13 implementation and its regression tests remain in the repository as dormant historical code.

## Implemented

- Added a persistent first-run and Settings checklist for Canvas, the authorized non-persistent in-app SIweb sign-in, a dedicated writable Campus Dashboard Calendar, local notifications, and optional DeepSeek consent/key setup. Canvas, SIweb, and DeepSeek secrets remain independently scoped to macOS Keychain.
- Added actionable isolated recovery states for revoked Calendar permission, denied notifications, Canvas expiry, SIweb expiry, source structural change, offline, provider failure, AI budget exhaustion, and failed background recovery. Every state names unaffected features and a safe recovery action.
- Expanded the central AI action center across pending, confirmed, corrected, conflict, fallback, ignored, and Calendar-written states. Empty `Other` and fallback analyses can be corrected, reprocessed, ignored, undone, or reset while preserving source provenance and reversible local personalization.
- Added Calendar impact previews and confirmation/undo reconciliation for schedule changes, cancellations, assignment deadlines, and exams. Exams use both an icon and `[EXAM]`; assignments use `[DEADLINE]`. Repeated reconciliation remains scoped and idempotent.
- Added aggregate-only release metrics and the observation protocol in `docs/stage-15r-evaluation.md`. Synthetic QA evidence is explicitly separated from real-user observation.
- Bumped the signed app to version `0.3.0` build `4` and removed the Microsoft callback URL scheme from the release bundle.

## Verification performed

- `./scripts/test.sh` — PASS, 226 tests in 20 suites.
- `./scripts/build-app.sh` — PASS, production app rebuilt and ad-hoc signed.
- `./scripts/verify-app.sh` — PASS, macOS application launch and Keychain smoke test.
- `codesign --verify --deep --strict "dist/Campus Dashboard.app"` — PASS.
- `git diff --check` — PASS before staging; the staged form is repeated immediately before the baseline commit.
- Credential-pattern scan excluding `.git`, `.build`, and `dist` — PASS, no secret-shaped match. Broad term review found only documentation, implementation field names, and explicitly synthetic test values.
- Generated/private-artifact scan — PASS, no SQLite/database, log, HAR/trace, private-key, certificate, provisioning-profile, or screenshot file in the repository candidate.
- Outlook production-path scan — PASS: production dependency injection is `nil`, the release flag is false, Settings exposes only a paused/no-traffic explanation, and the app has no URL callback or Outlook smoke route. No Outlook authorization or network check was run.

## Release identity

- Bundle: `dist/Campus Dashboard.app`
- Bundle identifier: `com.campusdashboard.desktop`
- Version/build: `0.3.0 (4)`
- Signature: ad-hoc; `codesign --verify --deep --strict` passed
- Executable SHA-256: `5343b33a5aeca9c394dfcea6b42cb1696a347a514c7bc8ebc21ab49328034f90`
- CDHash: `f0c420420cd0726f53449a2a4db74a0cdf02724f`
- Reconciliation implementation commit: `5df93d7fe544f8baad402e7b77c4b57622029af8` (`Repair Canvas SIweb course reconciliation`).
- The handoff-only evidence commit follows this implementation commit; the final handoff commit SHA is reported to the main conversation after creation.

## 2026-09-07 reconciliation repair

- Added schema-v13 persistent Canvas↔SIweb reconciliation state and append-only local decision audit. Canvas title-like `code` fields now fall back to extracting the module/section suffix from `name`; codes, code families, term prefixes, and titles are normalized deterministically.
- Automatic mapping requires a unique title on both sources plus an exact full code or compatible code family. A unique shared title with disagreeing code families becomes a local proposal. Duplicate titles or otherwise ambiguous candidates produce no mapping.
- Settings now shows both source records, confidence, provenance, and `Map`, `Keep separate`, `Undo`, and `Reset` controls with bilingual labels and stable accessibility identifiers. Existing source rows are never merged or deleted.
- Dashboard, course filters, and notification controls use one canonical Canvas identity after confirmation, while retaining raw Canvas and SIweb rows. Schedule-change signals are re-resolved against the confirmed SIweb course locally; mapping writes neither Calendar nor notification outbox work.
- Confirmed standalone schedule changes now use a distinct teal change label/icon and never inherit deadline semantics. Text-inferred dates remain confirmation-gated, and cancelled meetings cannot become a target.
- Production dashboard, notification, sync, AI, Calendar-safety, and notification-duplication metrics now admit only Canvas/SIweb provenance (case-insensitively for legacy databases). `Stage10Test`, QA test notifications, and other synthetic sources remain stored but are excluded from production presentation and metrics.
- Schema migration deactivates any historical one-to-many active mapping collision into a proposed state before installing one-to-one active indexes, so an upgrade cannot guess through ambiguity.

Focused verification:

- `./scripts/test.sh --filter CourseReconciliationTests` — PASS, 7 tests.
- `./scripts/test.sh --filter AcademicSignalTests` — PASS, 19 tests.
- `./scripts/test.sh --filter NotificationBackgroundTests` — PASS, 17 tests.
- `./scripts/test.sh --filter PersistenceTests` — PASS, 14 tests.
- `./scripts/test.sh --filter Stage15RReleaseTests` — PASS, 5 tests.
- Final `./scripts/test.sh` — PASS, 226 tests in 20 suites.
- Final build, launch/Keychain smoke, strict code-signing, and `git diff --check` — PASS.
- Targeted changed-code scans — PASS: no credential-shaped additions, no secret-shaped values in the new files, no new Outlook/Graph/mail endpoint, and no new network/WebKit/SystemConfiguration path. The only URL in the new reconciliation test is under `example.invalid`.
- Automated bilingual and accessibility assertions for the reconciliation controls and schedule-change semantics — PASS.

Repair limitations:

- No real source content, credentials, Keychain values, or personal Calendar event details were read or recorded by this delegated repair.
- The main conversation must still inspect the signed app with the user's existing lawful sessions and explicitly selected dedicated Campus Dashboard calendar. It must verify Map/Keep separate/Undo/Reset presentation and the mapped schedule-change lifecycle before accepting the stage.
- No Calendar event was created, updated, or cancelled by the repair or its tests. Outlook remained dormant. Stage 10 remains paused at 0/7.

## Aggregate evaluation

Synthetic verification is represented only by the automated tests above. It covers all nine recovery categories, bilingual critical labels, reversible ignored decisions, observed-timing persistence, Calendar preview-before-write, exam distinction, idempotence, and undo.

The pre-repair local app database contained mixed historical/development activity and cannot be presented as a clean real-user cohort. Its previously recorded aggregate-only snapshot was: 1,780 sync runs, 838 committed, 942 non-committed, 76.0-second average completed-run latency, 1 reviewed correction, 0 critical corrections from `Other`, 8 provider failures, 0 duplicate active Calendar bindings, 0 unsafe Calendar bindings, 0 duplicate notification keys, and 0 handling-time samples. The repaired metric queries now exclude non-Canvas/SIweb provenance, so those historical numbers must not be treated as the current filtered baseline. Day-7 retention, real-user correction recall, provider recovery rate, and handling-time percentiles remain unobserved.

## Mandatory checks not completed

- Final-candidate interactive bilingual/accessibility walkthrough of the new reconciliation controls: not performed in this delegated repair. Automated bilingual and accessibility contracts pass, but they are not substituted for the required real UI check.
- Existing-dedicated-calendar mapped schedule-change lifecycle: not performed. The repair deliberately made no EventKit change; the main conversation must preview and explicitly confirm any real create/update/cancel action with the user.
- Final-candidate aggregate-only Canvas/SIweb/notification/optional-DeepSeek recheck: not repeated by this repair. Any user-only Keychain, SIweb, Calendar, notification, MFA, or CAPTCHA prompt must remain with the user.
- Seven-day observed outcome review: not yet available and not fabricated.

## Exact user actions required

1. In the main conversation, open the rebuilt `Campus Dashboard 0.3.0 (4)` and inspect the reconciliation card in English and Simplified Chinese, including Map, Keep separate, Undo, Reset, provenance, confidence, and accessible non-color schedule-change semantics.
2. Complete any macOS Keychain, institutional SIweb/MFA/CAPTCHA, notification, or Calendar permission prompt personally. Do not send a password, token, Cookie, key, or private-source screenshot in chat, and grant Calendar access only for the dedicated Campus Dashboard calendar.
3. With a real ambiguous pair, verify zero mapping/Calendar writes; with one explicitly accepted unique mapping, preview and confirm the existing-dedicated-calendar schedule-change lifecycle. Only the main conversation may then accept Stage 15R or resume the seven-day trial.

## Files changed for Stage 15R

- `Resources/Info.plist`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/App/ReleaseReadiness.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasLocalTool.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Settings/SIwebAuthorizationView.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Tests/CampusDashboardTests/CalendarIntegrationTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/Stage15RReleaseTests.swift`
- `docs/stage-15r-evaluation.md`
- `.agent/handoffs/stage-15r.md`

Additional files changed by the reconciliation repair:

- `Sources/CampusDashboard/AI/AcademicSignalCoordinator.swift`
- `Sources/CampusDashboard/AI/AcademicSignalPersistence.swift`
- `Sources/CampusDashboard/App/DashboardDataService.swift`
- `Sources/CampusDashboard/Background/ProductionSyncRunner.swift`
- `Sources/CampusDashboard/Domain/CourseReconciliation.swift`
- `Sources/CampusDashboard/Domain/Models.swift`
- `Sources/CampusDashboard/Features/Schedule/CalendarPresentation.swift`
- `Sources/CampusDashboard/Features/Schedule/ScheduleView.swift`
- `Sources/CampusDashboard/Features/Shared/SpatialTimeGrid.swift`
- `Sources/CampusDashboard/Notifications/CampusNotificationService.swift`
- `Sources/CampusDashboard/Notifications/NotificationPersistence.swift`
- `Tests/CampusDashboardTests/AcademicSignalTests.swift`
- `Tests/CampusDashboardTests/CourseReconciliationTests.swift`

## Proposed main-thread current-context update

Keep Stage 15R `PARTIAL` and do not authorize a later stage. Record that the reconciliation implementation, 226-test automation, packaging, signature, scans, and Outlook dormancy pass. The main conversation should perform only the remaining real bilingual UI and existing-dedicated-calendar checks above, then decide whether to accept Stage 15R and resume Stage 10.
