# Stage 15R handoff — release readiness and validation closure

Status: `PARTIAL`

## Outcome

The release-candidate implementation, including the 2026-09-07 Canvas/SIweb reconciliation, acceptance-blocker, automatic-cadence, source-localization, and SIweb post-authorization health repairs, is complete and the automated, privacy, packaging, and signature gates pass. The current strict SIweb contract also passes an aggregate-only real read from the frozen candidate. The remaining acceptance gap is the main conversation's post-repair Settings/UI verification, real bilingual UI, automatic-cadence observation, and existing-dedicated-calendar walkthrough. This handoff therefore remains `PARTIAL` and does not start the seven-day trial.

No Outlook setup, authorization callback, token lookup, metadata probe, or background traffic is reachable from the production app in this release. The older Stage 13 implementation and its regression tests remain in the repository as dormant historical code.

## Implemented

- Added a persistent first-run and Settings checklist for Canvas, the authorized non-persistent in-app SIweb sign-in, a dedicated writable Campus Dashboard Calendar, local notifications, and optional DeepSeek consent/key setup. Canvas, SIweb, and DeepSeek secrets remain independently scoped to macOS Keychain.
- Added actionable isolated recovery states for revoked Calendar permission, denied notifications, Canvas expiry, SIweb expiry, source structural change, offline, provider failure, AI budget exhaustion, and failed background recovery. Every state names unaffected features and a safe recovery action.
- Expanded the central AI action center across pending, confirmed, corrected, conflict, fallback, ignored, and Calendar-written states. Empty `Other` and fallback analyses can be corrected, reprocessed, ignored, undone, or reset while preserving source provenance and reversible local personalization.
- Added Calendar impact previews and confirmation/undo reconciliation for schedule changes, cancellations, assignment deadlines, and exams. Exams use both an icon and `[EXAM]`; assignments use `[DEADLINE]`. Repeated reconciliation remains scoped and idempotent.
- Added aggregate-only release metrics and the observation protocol in `docs/stage-15r-evaluation.md`. Synthetic QA evidence is explicitly separated from real-user observation.
- Bumped the signed app to version `0.3.0` build `4` and removed the Microsoft callback URL scheme from the release bundle.

## Verification performed

- `./scripts/test.sh` — PASS, 236 tests in 20 suites.
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
- Executable SHA-256: `60402081d9ed538d24a7d682e480216d5d527ca4fe8fa088f14c91b880375c89`
- CDHash: `e6a68ab28caf0124e4884cca25f0ba167f95c41f`
- Reconciliation implementation commit: `5df93d7fe544f8baad402e7b77c4b57622029af8` (`Repair Canvas SIweb course reconciliation`).
- Acceptance-blocker implementation commit: `c4a345ad561749629cc9230bd2b299ade21cb872` (`Repair Stage 15R acceptance blockers`).
- Automatic-cadence and source-localization implementation commit: `3d6cbacd22f1e777ac7508968f94a760d6b63a30` (`Fix automatic sync cadence and source localization`).
- Calendar recovery-localization implementation commit: `c6b04b46328326d4e5931678f46aeab60789fab8` (`Localize Calendar recovery summary`).
- SIweb post-authorization health implementation commit: `7a6c8d5` (`Repair SIweb authorization health refresh`).
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

- `./scripts/test.sh --filter CourseReconciliationTests` — PASS, 8 tests.
- `./scripts/test.sh --filter AcademicSignalTests` — PASS, 19 tests.
- `./scripts/test.sh --filter NotificationBackgroundTests` — PASS, 17 tests.
- `./scripts/test.sh --filter PersistenceTests` — PASS, 14 tests.
- `./scripts/test.sh --filter Stage15RReleaseTests` — PASS, 7 tests.
- Final `./scripts/test.sh` — PASS, 231 tests in 20 suites.
- Final build, launch/Keychain smoke, strict code-signing, and `git diff --check` — PASS.
- Targeted changed-code scans — PASS: no credential-shaped additions, no secret-shaped values in the new files, no new Outlook/Graph/mail endpoint, and no new network/WebKit/SystemConfiguration path. The only URL in the new reconciliation test is under `example.invalid`.
- Automated bilingual and accessibility assertions for the reconciliation controls and schedule-change semantics — PASS.

Repair limitations:

- No real source content, credentials, Keychain values, or personal Calendar event details were read or recorded by this delegated repair.
- The main conversation must still inspect the signed app with the user's existing lawful sessions and explicitly selected dedicated Campus Dashboard calendar. It must verify Map/Keep separate/Undo/Reset presentation and the mapped schedule-change lifecycle before accepting the stage.
- No Calendar event was created, updated, or cancelled by the repair or its tests. Outlook remained dormant. Stage 10 remains paused at 0/7.

## 2026-09-07 acceptance-blocker repair

- Canvas term normalization now recognizes the real `(26/27-S1)` prefix. A database-backed six-pair regression confirms five deterministic compatible-family mappings and one proposed-only `COMP4120-411` versus `CSAI3122-311` Natural Language Processing conflict. The conflict is never auto-mapped.
- Production confirmation/history presentation and release metrics now exclude provider or model identities containing `fixture` or `synthetic`. A production-shaped database regression retains all 15 stored AI rows while exposing only the one non-fixture row; the 14 `Campus Dashboard deterministic fixture` / `fixture-v1` rows remain preserved but non-actionable. Explicit Stage 12 QA preview data is isolated behind its dedicated QA launch mode.
- Calendar readiness now requires full access and a `.valid` managed-calendar validation result, so the Calendar section and checklist share one state. Canvas/SIweb checklist completion remains security-strict and requires current readable Keychain configuration; stale `source_accounts` authorization cannot substitute for it. Healthy authorized-source helper text states that credential fields stay blank for security and no longer contradicts the checklist.
- A stored failed sync followed by a later successful sync is presented as historical/recovered, produces no current recovery action, and remains retained in SQLite. No history was deleted.
- Focused repair gates passed: 8 course-reconciliation tests, 7 Stage 15R release tests, 6 privacy-diagnostics tests, the validated-calendar readiness test, and 19 academic-signal tests. The final complete gate passed 231 tests in 20 suites, followed by production build, launch/Keychain smoke, strict code-sign verification, diff hygiene, credential/private-artifact scans, and prohibited-network/Outlook scans.
- No real service was accessed, no Outlook path was enabled, and no Apple Calendar write was performed during this repair.

## 2026-09-07 automatic-cadence and localization repair

- Root cause of the observed approximately 35-second loop: the scheduler polled every 30 seconds but considered cadence only from `last_completed_at`; a persistent single-source failure left that value empty, so every poll launched the complete multi-source sync again. The scheduler now uses the persisted most recent attempt as its cadence anchor. Successful and partial/failed automatic attempts therefore wait the configured 3,600-second target before another automatic run.
- Explicit development runs remain explicit. A network-recovery signal may bypass the cadence only when the persisted failure category is actually `offline`; launch/wake recovery and persistent `source_changed` failures do not bypass it. The whole sync runner is not invoked on suppressed ticks, so Canvas, SIweb, and post-sync AI processing cannot gain extra calls from the fix.
- A deterministic regression runs a Canvas-success/SIweb-`source_changed` partial result, evaluates scheduled ticks at 30, 65, 600, and 3,599 seconds without another run, then proves the next run occurs at 3,600 seconds. Existing immediate offline recovery and restart recovery tests remain passing. Source isolation continues to retain both source results; one source error does not erase the other's success.
- Settings now localizes diagnostic message and recovery-action keys separately before composing the Canvas/SIweb setup summary. English and Simplified Chinese regressions cover the SIweb safe-contract error, missing-source state, `Ready.`, and `No action needed.`; source-owned content remains unchanged.
- The repair did not inspect or mutate the user's real database. The main conversation's supplied observation remains the acceptance target: six Canvas plus six SIweb records, five confirmed active mappings and one inactive proposed Natural Language Processing conflict; fourteen retained fixture AI rows hidden and seven DeepSeek rows visible. No history-cleanup or automatic conflict action was added.
- Current SIweb `source_changed` was not treated as a parser defect because no private response was inspected and the connector contract was not weakened. It remains a user reauthorization/retest gate; if the exact authorized timetable page still fails afterward, investigate only with privacy-safe structural evidence.
- Final gates: `./scripts/test.sh` PASS (233 tests, 20 suites); production build PASS; app launch/isolated Keychain smoke PASS; strict ad-hoc signature PASS; diff hygiene, credential/private-artifact, and prohibited-network/Outlook scans PASS. The only new URL is `https://example.invalid` in a database-backed localization test. No real service, existing Keychain credential, Outlook path, or Apple Calendar event was accessed or changed.

## 2026-09-07 SIweb post-authorization health repair

- Root cause was stale persisted health, not a current parser mismatch. The frozen signed candidate's existing strict read-only SIweb smoke path successfully parsed 92 meeting instances with 0 cancellations and emitted no source content. Aggregate-only local database metadata showed that Settings was still reading an older `source_changed` sync result because the in-app authorization completion saved the eligible session in Keychain and refreshed checklist state, but never ran or persisted a new SIweb synchronization.
- Successful in-app SIweb authorization now launches one awaited SIweb-scoped manual synchronization, reloads persisted dashboard/diagnostic/background state, and then refreshes release readiness. Cancellation, missing eligible cookies, and Keychain-save failures do not start a synchronization.
- The scoped production runner configures and reads SIweb only. It does not refresh Canvas and cannot invoke the whole-run AI coordinators or Calendar outbox processor. Normal local reconciliation and notification-state refresh remain available after the SIweb commit. The existing exact-host, read-only GET, login-refusal, redirect-blocking, and strict parser contracts were not relaxed.
- Parser failures now include a bounded allowlisted structural fingerprint: only login-marker booleans, synthetic-contract marker booleans, table/header match counts, positional header masks, and bounded row-cell counts. It contains no cell text, URLs, headers, cookies, identifiers, or response excerpts. The local smoke tool may print this safe fingerprint on failure; persisted sync error summaries remain category-only.
- Added regressions proving that a successful authorization invokes only the SIweb-scoped runner, replaces stale `source_changed` health with `ready`, never invokes the whole-source runner, and cannot leak private marker/cell values through the structural diagnostic.
- Focused gates passed: 9 Stage 10 dashboard tests and 23 SIweb connector tests. Final `./scripts/test.sh` passed 236 tests in 20 suites. Production build, app launch/isolated Keychain smoke, strict code-sign verification, staged diff hygiene, credential/private-artifact scans, and changed-network/Outlook scans passed.
- Frozen candidate: Campus Dashboard `0.3.0 (4)`, ad-hoc signed, executable SHA-256 `60402081d9ed538d24a7d682e480216d5d527ca4fe8fa088f14c91b880375c89`, CDHash `e6a68ab28caf0124e4884cca25f0ba167f95c41f`. The aggregate-only real SIweb read was repeated from this exact signed candidate and passed with 92 meetings and 0 cancellations.
- This delegated repair did not inspect or record response content, expose a Keychain value, mutate either school source, enable Outlook, or perform an Apple Calendar write. Stage 15R remains `PARTIAL` until the main conversation verifies the repaired Settings flow and completes the other mandatory real UI/cadence/Calendar gates.

## Aggregate evaluation

The final narrow Calendar localization repair maps the recovery-center detail `Calendar access is not available.` to Simplified Chinese while preserving the English source key. Its focused regression also verifies the already-localized Calendar unaffected-features and recovery-action copy in the same generated recovery item. The focused test passed, followed by the complete 234-test/20-suite gate, production build, launch/isolated Keychain smoke, strict signature verification, diff hygiene, credential/private-artifact scan, and changed-network/Outlook scan. No network path, permission behavior, credential handling, source data, or Calendar mutation changed.

Synthetic verification is represented only by the automated tests above. It covers all nine recovery categories, bilingual critical labels, reversible ignored decisions, observed-timing persistence, Calendar preview-before-write, exam distinction, idempotence, and undo.

The pre-repair local app database contained mixed historical/development activity and cannot be presented as a clean real-user cohort. Its previously recorded aggregate-only snapshot was: 1,780 sync runs, 838 committed, 942 non-committed, 76.0-second average completed-run latency, 1 reviewed correction, 0 critical corrections from `Other`, 8 provider failures, 0 duplicate active Calendar bindings, 0 unsafe Calendar bindings, 0 duplicate notification keys, and 0 handling-time samples. The repaired metric queries now exclude non-Canvas/SIweb provenance, so those historical numbers must not be treated as the current filtered baseline. Day-7 retention, real-user correction recall, provider recovery rate, and handling-time percentiles remain unobserved.

## Mandatory checks not completed

- Final-candidate interactive bilingual/accessibility walkthrough of the new reconciliation controls: not performed in this delegated repair. Automated bilingual and accessibility contracts pass, but they are not substituted for the required real UI check.
- Existing-dedicated-calendar mapped schedule-change lifecycle: not performed. The repair deliberately made no EventKit change; the main conversation must preview and explicitly confirm any real create/update/cancel action with the user.
- Final-candidate aggregate-only Canvas/notification/optional-DeepSeek recheck: not repeated by this repair. The SIweb aggregate-only strict read passed, but its repaired Settings presentation still needs the main conversation's UI verification. Any user-only Keychain, SIweb, Calendar, notification, MFA, or CAPTCHA prompt must remain with the user.
- Re-enable automatic sync after personally reauthorizing SIweb, then observe at least one full configured interval. Confirm a persistent per-source failure does not produce another approximately 35-second loop and that Canvas remains independently usable.
- Seven-day observed outcome review: not yet available and not fabricated.

## Exact user actions required

1. In the main conversation, relaunch the frozen `Campus Dashboard 0.3.0 (4)` candidate and complete the SIweb authorization flow once more to exercise the repaired post-authorization synchronization. Satisfy any user-only Keychain/system/institutional prompt personally and do not share credentials, cookies, or private page content. Confirm that Settings leaves `source_changed`, reports SIweb ready/authorized, and the real six Canvas and six SIweb courses resolve to five confirmed mappings plus the one proposed Natural Language Processing code conflict without auto-mapping that conflict.
2. Confirm that the production AI confirmation queue does not show the 14 deterministic fixture rows, while no stored history is deleted. Inspect Canvas, SIweb, and Calendar status in both English and Simplified Chinese: healthy authorized sources must not say “not configured,” secret inputs must remain empty, and a valid selected iCloud dedicated calendar must be complete in both the Calendar section and checklist.
3. Complete any macOS Keychain, institutional SIweb/MFA/CAPTCHA, notification, or Calendar permission prompt personally. Do not send a password, token, Cookie, key, or private-source screenshot in chat, and grant Calendar access only for the dedicated Campus Dashboard calendar.
4. Re-enable automatic sync and observe that no short retry loop recurs after a persistent per-source failure; Canvas must remain independently usable and the next normal automatic attempt must respect the hourly target. With the proposed conflict, verify zero automatic mapping/Calendar writes; with one explicitly accepted unique mapping, preview and confirm the existing-dedicated-calendar schedule-change lifecycle. Only the main conversation may then accept Stage 15R or resume the seven-day trial.

## Files changed for Stage 15R

- `Resources/Info.plist`
- `Sources/CampusDashboard/AI/AIModels.swift`
- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/AI/AIPersistence.swift`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/App/ReleaseReadiness.swift`
- `Sources/CampusDashboard/App/Stage12QAData.swift`
- `Sources/CampusDashboard/Background/BackgroundModels.swift`
- `Sources/CampusDashboard/Background/BackgroundSyncScheduler.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasLocalTool.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebConnector.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebHTMLParser.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebLocalTool.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Settings/SIwebAuthorizationView.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Tests/CampusDashboardTests/CalendarIntegrationTests.swift`
- `Tests/CampusDashboardTests/NotificationBackgroundTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/PrivacyDiagnosticsTests.swift`
- `Tests/CampusDashboardTests/Stage15RReleaseTests.swift`
- `Tests/CampusDashboardTests/SIwebConnectorTests.swift`
- `Tests/CampusDashboardTests/Stage10DashboardDataTests.swift`
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

Keep Stage 15R `PARTIAL` and do not authorize a later stage. Record that the reconciliation, acceptance-blocker, cadence, localization, and SIweb post-authorization health implementations, 236-test automation, packaging, signature, scans, aggregate-only strict SIweb read, and Outlook dormancy pass. The main conversation should perform only the remaining repaired Settings verification, automatic-cadence observation, real bilingual UI, and existing-dedicated-calendar checks above, then decide whether to accept Stage 15R and resume Stage 10.
