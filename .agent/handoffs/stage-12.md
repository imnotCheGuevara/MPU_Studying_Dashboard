# Stage 12 handoff

Status: PASS

## Outcome

Stage 12 implementation and all acceptance checks are complete. Already-synchronized Canvas announcements now receive deterministic-first, versioned academic-signal analysis using the accepted Stage 11 DeepSeek boundary when enabled. The fixed taxonomy is `course_schedule_change`, `assignment_deadline`, `exam_time`, or `other`; one announcement can yield zero to eight non-`other` signals. Source announcement identity, text, language, and URL remain unchanged and separate from AI-derived records.

The controlled repair added a fixed, privacy-safe validator failure taxonomy, diagnosed `invalid_date` without persisting or printing provider output, and made one narrowly versioned prompt repair. The exact signed v3 bundle then produced a strictly validated real result with every inferred date pending and zero Calendar/notification writes. A separate in-memory `--stage12-ui-qa` mode has no provider, background, Calendar, or notification service; it passed live English/Simplified Chinese visual and accessibility inspection.

No Outlook/Stage 13 work was started. No Apple Calendar ownership or notification policy was changed. FlClash and macOS global proxy state were never read, opened, changed, paused, or closed; the existing explicit in-app exact-host DeepSeek direct route was used unchanged.

## Implementation

- Added additive schema v10 tables for versioned announcement analyses, active/inactive signals, adopted corrections, and append-only decision audit.
- Added strict signal types and validation. Root keys remain exact. Signal objects reject unknown keys and require category, evidence, key requirement, all-day flag, confidence, reason, and conflicts. Only the semantically nullable `inferredDate` and `timeZoneIdentifier` may be omitted and are normalized locally to `nil`; malformed dates, invalid time zones, `other` signals, extra fields, invalid category/primary combinations, excessive counts, and length/range violations fail closed.
- Added bounded HTML/text sanitation. Scripts, styles, iframes, remote-media tags, hidden markup, URLs, mail addresses, credentials/cookies/tokens, and tracking parameters are removed. Provider input contains only bounded title, visible body excerpt, minimum course name, locale, and fixed schema instructions. Stable source identity is replaced with a fixed local placeholder and is never transmitted.
- Added fixed text-only DeepSeek JSON Output prompt v3 through the accepted Stage 11 provider. The v3 repair requires a complete RFC 3339 timestamp with numeric offset or the exact null/false/null fallback; the strict validator was not loosened. Web search, tools, uploads, images, remote fetch, streaming, and thinking remain disabled. Existing exact-host HTTPS, Keychain, retry, single-flight, budget, cache, and aggregate-usage boundaries are reused.
- Validator failures persist only one of the fixed categories `root_missing_key`, `root_unknown_key`, `signal_missing_core_key`, `signal_unknown_key`, `invalid_category`, `invalid_primary_index`, `invalid_date`, `invalid_timezone`, `bounds_violation`, `type_mismatch`, or `other`. Neither provider output nor source content is included.
- Deterministic phrase classification runs first in English and Chinese. If DeepSeek is disabled, denied, unavailable, or rejected, the deterministic result is stored and displayed without affecting Canvas synchronization.
- Current analysis is idempotent by raw record/content/provider/model/prompt/schema identity. Updated content creates a new analysis and deactivates prior signals without deleting analyses, signals, decisions, or audit history. Explicit reprocessing reuses the durable provider cache when the same versioned input already validated.
- Every announcement-text date is persisted as inferred. It begins `pending`; only confirmed/corrected records appear in the app's Schedule. Academic signals do not enqueue EventKit work or create notification records, so no unconfirmed date can cross either boundary.
- Announcements UI now shows analysis status, category filtering, local-suggestion disclosure, evidence, key requirement, reason, conflicts, provenance, source navigation, reprocess, correct, reject, and inferred-date confirmation. The existing confirmation queue also displays pending academic-signal dates with confirm/correct/reject controls.
- Schedule presents confirmed inferred signals distinctly in purple. Official Assignment/Quiz deadline presentation changed from orange to red and retains the explicit `exclamationmark.circle.fill` symbol plus localized `Official deadline` semantics; Apple Calendar color behavior is unchanged.
- English/Simplified Chinese strings were added for Stage 12 UI and accessibility labels/hints. Source-authored announcement title/body bypass localization unchanged.
- AI-history clearing now also clears academic-signal analysis/signal/audit state through foreign-key cascade, independently of credentials and Calendar events.
- Production synchronization now uses the same configured Stage 11 coordinator/provider instances and analyzes only the latest lawful raw announcement by composite source identity. Stage 08 general parsing remains for learning tasks; announcements use the Stage 12 multi-signal schema rather than making a second legacy organization call.
- Added an isolated, synthetic in-memory signed-app QA mode for Stage 12 visual/accessibility checks. Runtime refresh is local-only and cannot start real background processing or provider calls.

## Files changed

- `Sources/CampusDashboard/AI/AcademicSignalModels.swift` (new)
- `Sources/CampusDashboard/AI/AcademicSignalPersistence.swift` (new)
- `Sources/CampusDashboard/AI/AcademicSignalCoordinator.swift` (new)
- `Sources/CampusDashboard/AI/AcademicSignalEvaluation.swift` (new)
- `Sources/CampusDashboard/AI/AcademicSignalLocalTool.swift` (new)
- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/AI/DeepSeekProvider.swift`
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/Stage12QAData.swift` (new)
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/Background/ProductionSyncRunner.swift`
- `Sources/CampusDashboard/Features/Announcements/AnnouncementsView.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Schedule/CalendarPresentation.swift`
- `Sources/CampusDashboard/Features/Schedule/ScheduleView.swift`
- `Sources/CampusDashboard/Features/Shared/SpatialTimeGrid.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift`
- `Tests/CampusDashboardTests/AcademicSignalTests.swift` (new)
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `.agent/handoffs/stage-12.md` (new)

Central planning/specification files and other-stage handoffs were not edited. The repository still has no tracked commit baseline and all project paths are untracked, as recorded by prior stages, so scope inspection used the explicit path inventory and forbidden-scope scans.

## Synthetic evaluation

Documented Stage 12 thresholds are precision >= 0.90 and recall >= 0.90 for every category. The 16-case multilingual evaluation covers English and Chinese examples, all four categories, multi-signal announcements, no-signal/`other`, schedule changes, assignment deadlines, exam/Quiz times, conflict, vague date, all-day, timed date, timezone, noisy HTML, prompt injection, repeated input, and changed content.

One-vs-rest signal metrics:

| Category | TP | FP | FN | TN | Precision | Recall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `course_schedule_change` | 5 | 0 | 0 | 11 | 1.00 | 1.00 |
| `assignment_deadline` | 4 | 0 | 0 | 12 | 1.00 | 1.00 |
| `exam_time` | 7 | 0 | 0 | 9 | 1.00 | 1.00 |
| `other` | 2 | 0 | 0 | 14 | 1.00 | 1.00 |

Primary-category confusion counts are diagonal: schedule-change 5/5, assignment-deadline 3/3, exam-time 6/6, other 2/2; all off-diagonal cells are zero. These are deterministic synthetic metrics, not a claim of real-world model accuracy.

## Automated verification

Final controlled-repair logs are retained under `/tmp/campus-stage12-controlled-repair.SIxygO`.

```sh
./scripts/test.sh --filter AcademicSignalTests
# PASS: 14 tests / 1 suite, 0 failures, 0.040s.

swift package clean
swift build --jobs 1
# PASS: final clean Debug build, 40.79s, no compiler warnings/errors.

./scripts/test.sh
# PASS: 196 tests / 17 suites, 0 failures, 0.550s test execution.

./scripts/build-app.sh
# PASS: Release build, 45.55s; ad-hoc signed dist/Campus Dashboard.app created.

./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: Launch Services/packaged Keychain smoke, strict signature, and both plists.
# Final executable SHA-256: bc577c63aaf11ef3266ef9cc5d3e3e84e0cd3736b6b105683a3b7df631c1dc04
# CDHash: 6cebac105e219407938541a47689caf15f7fa261
```

Focused coverage proves fixed taxonomy and multi-signal behavior; strict positive/negative schema validation; nullable-field normalization with core-field/unknown-field rejection; prompt-injection isolation; minimum outbound fields; HTML/URL/email/token/cookie/tracker stripping; disabled/unavailable provider isolation; latest-raw source identity selection; unchanged cache/idempotency; changed-content re-evaluation; audit preservation; confirm/correct/reject persistence; all-day/timed/timezone/conflict handling; source text preservation; bilingual UI strings; official-deadline red/symbol semantics; and zero unconfirmed Schedule/Calendar/notification eligibility.

## Security, privacy, localization, and scope scans

```sh
! rg -n '<credential/private-key patterns>' --hidden \
  --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n 'import (EventKit|UserNotifications)|Mail\.|Microsoft Graph|Outlook|study planning|Phase 2' \
  Sources/CampusDashboard/AI Tests/CampusDashboardTests/AcademicSignalTests.swift
! rg -n 'SCDynamicStore|SCPreferences|SystemConfiguration|networksetup|CFNetworkCopySystemProxySettings|CFNetworkExecuteProxyAutoConfiguration|setenv\(|ProcessInfo.*environment' \
  Sources/CampusDashboard/AI Sources/CampusDashboard/App
! rg -n 'proxyAddress|proxyHost|proxyPort|proxyPassword|authorization_header|cookie_value|proxy_credentials|response_json|output_json|source_summary' \
  Sources/CampusDashboard/Privacy
! rg -n '[[:blank:]]+$' <Stage-12 new files>
git diff --check
otool -L "dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" | rg SystemConfiguration
# PASS: credentials, forbidden Stage 13/Phase 2/framework references, global-proxy APIs,
# diagnostic payload/body fields, linked SystemConfiguration, and whitespace are absent.
```

The Stage 12 bilingual test verifies every new user-visible key has a distinct Simplified Chinese value and confirms arbitrary multilingual source titles/bodies pass through unchanged. Existing Stage 10R localization/source-preservation and Schedule suites pass in the 196-test full regression. Live signed-app AX and visual inspection passed in English and Simplified Chinese using the isolated synthetic mode. Announcements exposed category, provenance, conflict, evidence, pending-date semantics, and confirm/correct/reject actions; the confirmation queue exposed the pending record and actions; Schedule exposed separate `Official deadline` and `Confirmed inferred deadline` accessibility descriptions. Source title/body remained verbatim across the language switch. Visual inspection found no clipping or overlap in the Stage 12 announcement presentation. The isolated QA process was stopped after inspection.

## Calendar and notification gate evidence

- A persisted provider suggestion with an inferred date was `pending` immediately after analysis.
- Before confirmation: app Schedule event count 0; Calendar outbox count 0; notification-delivery count 0.
- After explicit local confirmation: app Schedule count 1 with `confirmedInferredDeadline`; Calendar outbox and notification-delivery counts remain 0 because Stage 12 does not extend those ownership/policy boundaries.
- Real smoke aggregate: `unauthorizedCalendarOutboxDelta=0`, `unauthorizedNotificationDelta=0`, `sourceContentHashUnchanged=true`, and every inferred date count equaled pending inferred-date count.

## Real Canvas-announcement smoke history and controlled repair

The production preflight read aggregate state only: schema 9 before migration, 7 active Canvas announcements, DeepSeek enabled, school-policy consent confirmed, and the already accepted in-app exact-host direct route enabled. No announcement title/body, URL, identity, key, provider response, or proxy detail was printed.

The first real Stage 12 run used prompt/schema v1. Some provider results omitted nullable fields and were rejected; deterministic results remained active. The compatibility repair preserved exact root keys, unknown-field rejection, and all core required fields, allowing only absent inferred-date/time-zone fields to normalize to null. The prompt/schema/cache identity advanced to v2/2, the entire offline suite and signed build were rerun, and exactly one post-repair smoke was attempted.

Final v2 aggregate evidence from the signed bundle:

```text
status=blocked_provider_validation
analyzedAnnouncements=1
providerSchemaValidated=false
activeSignalCount=5
inferredDateCount=0
pendingInferredDateCount=0
unauthorizedCalendarOutboxDelta=0
unauthorizedNotificationDelta=0
sourceContentHashUnchanged=true
containedPrivateContent=false
containedCredential=false
```

At that checkpoint, the final v2 result failed the mandatory real-provider validation criterion even though every safety property held. No further real announcement was sent until the later explicitly authorized controlled repair.

During attempted live UI inspection, the Computer Use accessibility request transparently launched the signed app while the Mac was locked. That normal app startup triggered the already enabled background synchronization/AI path over the seven locally synchronized announcements. Aggregate provider usage increased from the Stage 11 baseline `1 request / 213 input / 126 output tokens` to `10 requests / 2614 input / 1121 output tokens`; two v1 academic-signal results validated and entered the durable cache, while five v1 academic analyses and the one explicit v2 smoke analysis failed local validation. The remaining successful usage can include the existing Stage 08 task organization path. This exceeded the intended single smoke due to startup behavior, although it remained within the user's existing enabled consent/budgets and did not expose content or credentials. The verification app process was explicitly closed afterward to prevent further background work. This deviation remains recorded and was not rewritten or omitted during the controlled repair.

After explicit main-thread authorization, the repair proceeded under a strict two-call ceiling. Offline adversarial tests first proved the fixed failure taxonomy and absence of dynamic/private error text. The one diagnostic v2 request failed closed as `invalid_date`; its evidence artifact contained only allowlisted aggregates/booleans and that fixed category. It reported zero usage delta because provider accounting is committed only after local schema validation, while the failed analysis proves the request completed and was rejected locally. No response body, announcement content, credential, or dynamic error was logged or persisted.

The single repair changed only date-format instructions and version/cache identity: v3 requires an RFC 3339 timestamp with numeric offset, gives an exact example, and requires null/false/null when the text is insufficient. Unknown-key rejection, core required fields, bounds, category rules, and date/time-zone validation remain strict. The complete clean build, 196-test suite, Release packaging, signature/Keychain verification, and scans were rerun before the single final live call.

Final v3 aggregate evidence from executable SHA-256 `bc577c63aaf11ef3266ef9cc5d3e3e84e0cd3736b6b105683a3b7df631c1dc04`:

```text
status=pass
analyzedAnnouncements=1
providerSchemaValidated=true
validatorFailureCategory=nil
activeSignalCount=5
inferredDateCount=1
pendingInferredDateCount=1
providerRequestDelta=1
inputTokenDelta=482
outputTokenDelta=226
unauthorizedCalendarOutboxDelta=0
unauthorizedNotificationDelta=0
sourceContentHashUnchanged=true
containedPrivateContent=false
containedCredential=false
```

Aggregate persisted provider usage after the final call was `11 requests / 3096 input / 1347 output tokens`. No further provider request was made.

## Remaining limitations

- The deterministic 16-case measurements are synthetic regression evidence, not real-world accuracy estimates.
- Provider outputs remain intentionally unusable when they do not satisfy the strict local schema; deterministic signals remain available in that failure mode.
- The earlier locked-screen startup deviation above remains part of the permanent evidence history.

All mandatory Stage 12 acceptance items now have evidence. Only the main project conversation may accept this handoff and authorize Stage 13.
