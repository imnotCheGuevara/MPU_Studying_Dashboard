# Stage 15R handoff — release readiness and validation closure

Status: `PARTIAL`

## Outcome

The release-candidate implementation is complete and the automated, privacy, packaging, and signature gates pass. The remaining gap is user-only macOS/real-service authorization: the rebuilt candidate is currently waiting on Keychain access, SIweb still needs an interactive reauthorization, and Calendar permission is revoked. Therefore this handoff does not claim release acceptance or completion of the mandatory final bilingual/accessibility and real-service walkthrough.

No Outlook setup, authorization callback, token lookup, metadata probe, or background traffic is reachable from the production app in this release. The older Stage 13 implementation and its regression tests remain in the repository as dormant historical code.

## Implemented

- Added a persistent first-run and Settings checklist for Canvas, the authorized non-persistent in-app SIweb sign-in, a dedicated writable Campus Dashboard Calendar, local notifications, and optional DeepSeek consent/key setup. Canvas, SIweb, and DeepSeek secrets remain independently scoped to macOS Keychain.
- Added actionable isolated recovery states for revoked Calendar permission, denied notifications, Canvas expiry, SIweb expiry, source structural change, offline, provider failure, AI budget exhaustion, and failed background recovery. Every state names unaffected features and a safe recovery action.
- Expanded the central AI action center across pending, confirmed, corrected, conflict, fallback, ignored, and Calendar-written states. Empty `Other` and fallback analyses can be corrected, reprocessed, ignored, undone, or reset while preserving source provenance and reversible local personalization.
- Added Calendar impact previews and confirmation/undo reconciliation for schedule changes, cancellations, assignment deadlines, and exams. Exams use both an icon and `[EXAM]`; assignments use `[DEADLINE]`. Repeated reconciliation remains scoped and idempotent.
- Added aggregate-only release metrics and the observation protocol in `docs/stage-15r-evaluation.md`. Synthetic QA evidence is explicitly separated from real-user observation.
- Bumped the signed app to version `0.3.0` build `4` and removed the Microsoft callback URL scheme from the release bundle.

## Verification performed

- `./scripts/test.sh` — PASS, 219 tests in 19 suites.
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
- Executable SHA-256: `f242fba9918e3de51c980368b21cf76ef4a8828299c52d24dfd918d231109923`
- CDHash: `6ad7527a48729b35e4cf3a8d7ca3d25f0109609e`
- Git release-baseline commit: recorded after the initial commit below

## Aggregate evaluation

Synthetic verification is represented only by the automated tests above. It covers all nine recovery categories, bilingual critical labels, reversible ignored decisions, observed-timing persistence, Calendar preview-before-write, exam distinction, idempotence, and undo.

The existing local app database contains mixed historical/development activity and cannot be presented as a clean real-user cohort. Its aggregate-only snapshot was: 1,780 sync runs, 838 committed, 942 non-committed, 76.0-second average completed-run latency, 1 reviewed correction, 0 critical corrections from `Other`, 8 provider failures, 0 duplicate active Calendar bindings, 0 unsafe Calendar bindings, 0 duplicate notification keys, and 0 handling-time samples. These values are baseline diagnostics, not evidence that the seven-day acceptance thresholds were met. Day-7 retention, real-user correction recall, provider recovery rate, and handling-time percentiles remain unobserved.

## Mandatory checks not completed

- Final-candidate bilingual and accessibility walkthrough: the previous process was intentionally discarded after rebuilding. The `0.3.0 (4)` process launched, but macOS blocked its startup while reading the existing DeepSeek Keychain item. No prompt was accepted and no credential was exposed.
- Final-candidate Canvas/SIweb/Calendar/notification/optional-DeepSeek real-service pass: not completed because the same user-only authorization gate prevents a valid final-candidate walkthrough; SIweb also reports a structural/session recovery need and Calendar permission is revoked.
- Seven-day observed outcome review: not yet available and not fabricated.

## Exact user actions required

1. Bring the already running `Campus Dashboard 0.3.0 (4)` to the foreground and approve its macOS Keychain access prompt for the existing Campus Dashboard item (choose the persistent allow option only if you trust this rebuilt local candidate). Do not send any password, token, Cookie, key, or prompt screenshot in chat.
2. In the app's setup checklist, complete SIweb reauthorization yourself in the embedded non-persistent school sign-in page, including any MFA/CAPTCHA, and re-enable Calendar access for the dedicated Campus Dashboard calendar. Do not grant access to unrelated calendars.
3. Reply only `授权完成，继续 Stage 15R 实机检查`. The main conversation can then run the final aggregate-only bilingual/accessibility and real-service validation without printing source content.

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

## Proposed main-thread current-context update

Keep Stage 15R `PARTIAL` and do not authorize a later stage. Record that implementation, 219-test automation, packaging, signature, scans, Outlook dormancy, and the initial Git baseline pass; list the three exact user actions above as the remaining gate. After those checks pass, the main conversation may accept Stage 15R and decide whether the app is ready for ordinary use.
