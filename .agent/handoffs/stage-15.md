# Stage 15 handoff — academic signal classification and schedule mapping

Status: `PARTIAL`

## Outcome

Stage 15 implementation is complete and the frozen release candidate passes the full automated, build, launch, Keychain, and strict code-signing checks. A 2026-09-07 authorized validation pass added a successful aggregate-only live Canvas smoke and confirmed independent-source failure handling, but the stage remains `PARTIAL`: the existing SIweb session now redirects to login, DeepSeek consent is not current, and the signed-app interactive bilingual walkthrough remains blocked because macOS ScreenCaptureKit returns capture error `-3811` and the accessibility bridge cannot complete.

Stage 10 remains paused at 0/7. No Stage 10 validation was started. Outlook remains dormant: no mail, Microsoft Graph, login, or authentication activity occurred, and no Outlook code was changed or inspected.

## Implemented

- Added deterministic academic-signal handling for assignment, exam, schedule-change, cancellation, and other announcements, including exact multilingual cancellation wording without broad cancellation inference.
- Added SIweb course and meeting mapping with ambiguity represented explicitly. Ambiguous section/meeting matches remain pending and cannot write to Calendar.
- Added supervised local corrections for signal type, date/time, time zone, and course, with versioned provenance, persistence, replay, undo, and reset.
- Restricted DeepSeek disclosure to course code, local section, at most 24 meeting IDs, start/end values, and time zones. Location, URLs, identifiers, announcement history, and unrelated content are not disclosed. A changed disclosure contract requires renewed consent.
- Added privacy-safe provider failure categories and recovery actions without exposing raw provider payloads.
- Added confirmed exam presentation, cancellation/change overlays that preserve the original SIweb meeting identity, duration, and location, and dual provenance linking the SIweb event source with the related Canvas announcement.
- Added schema version 11 mapping and personalization storage, transition auditing, safe Calendar reconciliation, F1 evaluation, and the frozen 20-case synthetic fixture.
- Added English and Chinese UI/localization coverage for Stage 15 corrections, ambiguity, recovery, exam, and change-link states.

## Evaluation

Frozen fixture: `Tests/CampusDashboardTests/Fixtures/Stage15/academic-signals-v1.json`

Fixture SHA-256: `157e18c74c986af872ef211cd2d7f89cbfc4f4e5e5c405be5a4605a2fd431478`

Executable SHA-256: `769d26df99ed0e35fbe4d233622ef94719275df7e1f789b511faa686d084fdc8`

- Baseline aggregate accuracy: 17/20. Post-change aggregate accuracy: 20/20.
- Post-change precision, recall, and F1 are 1.000 for assignment, exam, schedule, and other on this synthetic fixture.
- Representative recovery groups: 8/8 passed.
- Correction lifecycle phases: 5/5 passed.
- Ambiguous mapping regression cases produced zero unsafe Calendar writes; reconciliation regression cases produced zero duplicate events.
- Warm focused-test body times were 0.014 s, 0.012 s, and 0.012 s (median 0.012 s); whole-command times were 0.37 s, 0.34 s, and 0.34 s (median 0.34 s).
- The documented 44.7–89.7 seconds avoided is an estimate against a 45–90 second manual analysis assumption, not an observed human/resume metric. Stage 10 evidence is still required before making a real workflow-efficiency claim.

Detailed baseline, post-change, recovery, correction, and timing methodology is in `docs/stage-15-evaluation.md`.

## Verification performed

- `./scripts/test.sh --filter AcademicSignalTests` — PASS, 19 tests, 0 failures.
- `./scripts/test.sh` — PASS, 213 tests across 18 suites, 0 failures.
- `./scripts/build-app.sh` — PASS; produced the canonical bundle `dist/Campus Dashboard.app`.
- `./scripts/verify-app.sh` — PASS; the signed application launched and completed the Keychain smoke.
- `codesign --verify --deep --strict 'dist/Campus Dashboard.app'` — PASS.
- Bundle identifier: `com.campusdashboard.desktop`; ad-hoc signature; CDHash `570443c11320ac771e1aad7d2cef9a99822b5e00`.
- Targeted privacy/prohibited-network scans — PASS. No credential-like fixture data, forbidden DeepSeek disclosure fields, Outlook/Graph/mail access in the changed academic workflow, system proxy API use, or SystemConfiguration linkage was found.
- Automated bilingual localization and accessibility semantics are covered by the passing suite.

The prompt's no-space path, `dist/CampusDashboard.app`, does not exist and therefore cannot pass strict verification. The repository's required canonical bundle is `dist/Campus Dashboard.app`; strict verification passed on that exact artifact.

## Authorized validation-only pass — 2026-09-07

- Normal signed production app launch: PASS. `dist/Campus Dashboard.app` opened to the Today page and remained running without a startup crash. A system static screenshot worked for transient local inspection; it was not copied into the repository or handoff and contained no reusable validation evidence.
- Interactive UI control: BLOCKED. The accessibility bridge first returned `AXError.cannotComplete`; a clean path-based retry reproduced ScreenCaptureKit `SCStreamErrorDomain -3811`. Therefore the English/Simplified Chinese interaction walkthrough (failure recovery actions, empty-result correction, save/restart, undo/reset, ambiguity review, exam styling/semantics, and source links) was not represented as passed. No visual evidence was fabricated.
- Canvas live read-only smoke: PASS. The signed executable completed the existing aggregate-only connector smoke with 6 courses, 7 tasks, and 8 announcements. A normal production refresh independently committed a 21-object Canvas read with 0 inserts, 0 updates, and 0 cancellations in that run.
- SIweb live read-only smoke: BLOCKED safely with `loginRedirect`. No login, CAPTCHA, MFA, session replacement, form submission, or bypass was attempted. The Canvas pass completed independently, demonstrating that one source failure did not block the other.
- DeepSeek synthetic smoke: BLOCKED safely with `consent_required`. The stored direct-HTTPS preference is enabled, but the tool recorded 0 requests and 0 input/output tokens; therefore no private content or credential was transmitted and real exact-host routing is not yet claimed as verified.
- Calendar/notification boundary: the local database contains exactly one managed-calendar identity. The connector and blocked AI smokes did not invoke a Calendar or notification write path. The available lifecycle tool was deliberately not run because it creates an additional control calendar, which is outside this validation task's restriction to the already dedicated Campus Dashboard calendar. No Calendar event or calendar was created, modified, or deleted by this pass.
- The mandatory ambiguous zero-write case, uniquely mapped confirmed cancellation/change, confirmed exam Apple Calendar marker, same-bound-event update, and repeat/correct/undo/reset real lifecycle remain unverified. Existing automated evidence still covers those behaviors, but it is not substituted for the required real acceptance.
- Outlook remained untouched and dormant. Stage 10 remained paused at 0/7; no seven-day counter or Stage 10 acceptance phase was started.

Privacy-safe commands/results used in this pass:

- Signed executable `--canvas-smoke-test` — PASS with aggregate counts only.
- Signed executable `--siweb-smoke-test` — safe failure `loginRedirect`.
- Signed executable `--deepseek-smoke-test <sandbox result>` — safe block `consent_required`, direct HTTPS preference true, request/token counts 0.
- Normal Launch Services start plus local static capture — production Today page loaded; interactive capture retry failed with `-3811`.
- Aggregate-only SQLite queries — one managed-calendar identity; recent Canvas success and SIweb failure remained independent. No source body, URL, identifier, credential, Cookie, token, or Calendar event detail was printed or recorded.

No product files were changed, and the full test/build/signature suite was not rerun because this pass found no product defect and the frozen artifact was not modified.

## Verification not performed / limitation

- Live Canvas is now verified. Live SIweb requires the user to refresh the existing authorized SIweb session; live synthetic DeepSeek requires the user to renew the in-app disclosure consent and approve Keychain access locally. No secret should be placed in chat.
- The requested interactive English/Chinese visual and accessibility walkthrough still cannot proceed until Screen Recording/Accessibility access for Codex Computer Use works without ScreenCaptureKit `-3811` / `AXError.cannotComplete`.
- After those local authorizations are restored, rerun only the missing SIweb/DeepSeek smokes and one hands-on bound-event lifecycle in the existing dedicated Campus Dashboard calendar. This is the single remaining user handoff: restore the three local permissions/authorizations, then resume this Stage 15 validation task. Until that occurs, the release candidate must not be treated as fully accepted.

## Files changed

- `Package.swift`
- `Sources/CampusDashboard/AI/AcademicSignalCoordinator.swift`
- `Sources/CampusDashboard/AI/AcademicSignalEvaluation.swift`
- `Sources/CampusDashboard/AI/AcademicSignalModels.swift`
- `Sources/CampusDashboard/AI/AcademicSignalPersistence.swift`
- `Sources/CampusDashboard/AI/DeepSeekAcademicSignalProvider.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Features/Announcements/AnnouncementsView.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Schedule/CalendarPresentation.swift`
- `Sources/CampusDashboard/Features/Schedule/ScheduleView.swift`
- `Sources/CampusDashboard/Features/Shared/SpatialTimeGrid.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Sync/OutboxProcessor.swift`
- `Tests/CampusDashboardTests/AcademicSignalTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/Fixtures/Stage15/academic-signals-v1.json`
- `Tests/CampusDashboardTests/Fixtures/Stage15/manifest.json`
- `docs/stage-15-evaluation.md`
- `.agent/handoffs/stage-15.md`

## Main-thread follow-up

Do not update `.agent/CURRENT.md` to `COMPLETE`. The main thread should retain Stage 15 as `PARTIAL`, note that Canvas live smoke now passes, and schedule only the missing SIweb reauthorization smoke, synthetic DeepSeek consent smoke, English/Chinese signed-app walkthrough, and existing-dedicated-calendar lifecycle. Stage 10 must remain paused until separately resumed by the user.
