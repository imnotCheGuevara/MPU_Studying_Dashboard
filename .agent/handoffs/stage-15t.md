# Stage 15T handoff

Status: `PASS`

## Outcome

Stage 15T implements deterministic Canvas assignment-placeholder suppression and the focused Needs Review queue while preserving the complete Announcements feed. All mandatory automated checks and the available synthetic signed-app walkthrough passed. No central control file was edited, no real source or EventKit operation was performed, and the remaining Stage 15S real Calendar lifecycle gate remains explicitly out of scope.

## Product behavior

- Canvas assignment decoding now carries complete/incomplete placeholder evidence. Classification is conservative and fail-open: a row is suppressed only when the standard evidence fields (`due_at`, `description`, `submission_types`, `quiz_id`, `external_tool_tag_attributes`, and `annotatable_attachment_id`) were all present and the assignment has no official due date, meaningful description, attachment, linked quiz/external activity, meaningful submission type, or bilingual offline/reading/preparation/attendance action cue. Canvas does not need to return a non-standard `attachments` array for evidence to be complete; when that compatibility extension is present, it remains an additional positive attachment signal. An official `annotatable_attachment_id` or a link inside an otherwise text-empty HTML description also keeps the assignment visible.
- Placeholder state is recomputed on every sync and historical reload. Source identity, stable local task ID, source URL, and the persisted per-task `Always show in task list` preference survive placeholder-to-active and active-to-placeholder transitions.
- Initial placeholders create no Calendar outbox or new-task/deadline notification work. The first later transition to actionable uses the existing new-task notification path exactly once; repeated active refreshes and later placeholder-to-active cycles cannot duplicate it. Returning to placeholder removes an existing Calendar binding once. Placeholders are excluded from Today, Schedule, Calendar presentation/write boundaries, notification reconciliation, and AI provider input/context.
- Tasks keeps placeholders out of its normal rows unless the persisted override is enabled. Suppressed rows appear in collapsed per-course `Placeholder assignments` groups with an explanation and an `Always show in task list` control. Enabling the override moves the row into the normal list without duplicating it, marks it as a placeholder, and retains the same control so the choice is reversible. Task-type filters apply consistently to both partitions.
- The former AI confirmation queue is presented as `Needs Review`, with a sidebar badge. It contains only unresolved actionable signals, provider-unavailable failures, and `other` corrections. Confirmed, corrected, rejected, or ignored work leaves the queue. Announcements remains the complete original feed and retains its analysis/history controls.

## Persistence and model semantics

- Schema version advanced from 14 to 15.
- `learning_tasks` adds `placeholder_state`, evidence completeness and positive-signal columns, and `placeholder_always_show`, plus an index over placeholder/source state.
- `placeholder_metrics` stores only aggregate `suppressed_total`, `reactivated_total`, and `current_suppressed` counts with an update timestamp. It contains no source text, URL, user identifier, estimate, or claim of time saved.
- Older or incomplete records default active and are never suppressed merely because evidence is absent. Stored complete evidence is deterministically recomputed when the database is reopened.
- `LearningTask` exposes `isPlaceholder`, `placeholderAlwaysShow`, and `appearsInNormalTaskList`. `TaskPlaceholderEvidence` is propagated through normalized source payloads.

## Changed files

Product:

- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardDataService.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/App/Stage12QAData.swift`
- `Sources/CampusDashboard/Calendar/CampusCalendarService.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasDTOs.swift`
- `Sources/CampusDashboard/Domain/Models.swift`
- `Sources/CampusDashboard/Features/Confirmations/ConfirmationQueueView.swift`
- `Sources/CampusDashboard/Features/Schedule/CalendarPresentation.swift`
- `Sources/CampusDashboard/Features/Tasks/TasksView.swift`
- `Sources/CampusDashboard/Notifications/CampusNotificationService.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Services/ServiceContracts.swift`
- `Sources/CampusDashboard/Sync/SyncEngine.swift`
- `Sources/CampusDashboard/Sync/SyncModels.swift`
- `Sources/CampusDashboard/Sync/SyncSourceReaders.swift`

Tests:

- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `Tests/CampusDashboardTests/Stage15TTests.swift`

Handoff only:

- `.agent/handoffs/stage-15t.md`

## Verification

- `swift test --filter PersistenceTests` — PASS, 15/15 focused persistence tests during the original Stage 15T implementation; the post-review full-suite rerun below also includes these tests.
- `./scripts/test.sh --filter Stage15TTests` — PASS, 6/6 Stage 15T tests, including the second-round list-partition, one-time activation-notification, and cancel/reappear metric regressions.
- `./scripts/test.sh` — PASS, 250 tests in 21 suites after the second-round correction. This includes the full Stage 15S regression coverage for exact-meeting cancellation, make-up events, inferred-date confirmation, exam styling, dedicated-calendar isolation, source read-only behavior, bilingual localization/accessibility, and Outlook dormancy.
- `CONFIGURATION=release ./scripts/build-app.sh` — PASS; production bundle created and signed at `dist/Campus Dashboard.app`.
- `./scripts/verify-app.sh` — PASS; signed bundle launch and Keychain smoke verification succeeded.
- `codesign --verify --deep --strict --verbose=2 "dist/Campus Dashboard.app"` — PASS.
- `git diff --check` — PASS.
- Targeted added-line credential/private-data scan — PASS; no credential-shaped additions. The Stage 15T test uses only `canvas.invalid` synthetic URLs.
- Targeted added-line prohibited-network scan — PASS; no added URLSession, external host, Outlook/mail, proxy, or FlClash behavior.
- Central-file scope scan — PASS; no `AGENTS.md`, `.agent/CURRENT.md`, `.agent/STATUS.md`, `.agent/ROADMAP.md`, other central control file, stage contract, or project specification was modified.

## Test evidence

- The table-driven classification matrix covers each positive signal, incomplete evidence, no-submission offline/reading work, and a truly empty shell. Decoder regressions additionally prove that a standard complete Canvas object without an `attachments` key can be suppressed, while `annotatable_attachment_id` and an HTML link each keep a task visible.
- Persistent tests cover restart recomputation, stable identity, repeated-sync idempotency, persisted override, placeholder-to-active and active-to-placeholder transitions, cancellation/reappearance, and aggregate metrics. The deterministic scenario records suppressed totals `2`, reactivated totals `1`, and current suppressed `1`: the two suppression increments are the initial suppression and the later active-to-placeholder transition. Two complete absences cancel the row and reduce current suppressed to `0`; unchanged reappearance restores it to `1` without changing either historical total.
- The transition tests prove zero initial outbox work, zero AI provider requests, one Calendar upsert on activation, one Calendar removal on suppression, and one new-task notification on the first actionable transition. Repeated active refresh and a later placeholder-to-active cycle keep the notification total at one.
- Task-list partition tests prove that always-shown placeholders and grouped placeholders are disjoint, and that assignment/quiz filters apply identically to both partitions.
- Needs Review policy/model tests cover provider-unavailable and `other` inclusion, removal of resolved decisions, badge/model filtering, and retention of the source announcement.

## Signed-app walkthrough

The exact release bundle was launched with the isolated `--stage12-ui-qa` database; no real source content or network service was used.

- English Tasks showed only the official assignment in the normal list and a collapsed `Placeholder assignments · 多语言 Synthetic Course 原文 (1)` group. Expanding it exposed `Synthetic empty assignment shell`, the exclusion explanation, and the persisted `Always show in task list` checkbox. Enabling that checkbox moved the shell into the normal list with its placeholder marker and control while removing the group; disabling it restored exactly one grouped row.
- English Needs Review showed badge `1` and exactly one pending conflict/uncertain item with original-source, preview, correction, and ignore affordances. The confirmed analysis did not appear there.
- English Announcements retained the complete synthetic source announcement, both confirmed and unresolved analyses, status/actions, and original-source link.
- After switching through the signed app's language control, Chinese Tasks showed `暂存占位作业` and Chinese Needs Review showed `待确认`, the same badge/count, localized explanation, and correction actions. Accessibility state exposed the complete labels in both languages.

## Limitations and next gate

- No live Canvas/SIweb traffic, credentials, private source text, or real Calendar/notification mutation was used. Synthetic `.invalid` links and fixed-output analysis were used for QA.
- Aggregate metrics demonstrate deterministic transition accounting only. They do not establish accuracy, time saved, or trial outcomes, and no such estimate is stored or reported.
- Stage 15T does not accept Stage 15/15R/15S, resolve the remaining real EventKit lifecycle gate, start the seven-day trial, or freeze a release. The main conversation must review this handoff and decide acceptance.
