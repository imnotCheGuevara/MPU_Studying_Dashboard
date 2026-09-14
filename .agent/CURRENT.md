# Campus Dashboard current context

Updated: 2026-09-14 Asia/Macau.

## Active state

- **Stage 16W: ACTIVE / PARTIAL — USER APPROVED 2026-09-12.** Preview 1 remains published and Preview 2 remains an unpublished historical draft. The reuse-first Windows candidate now includes Canvas plus an advanced read-only SIweb timetable beta with independent Credential Manager entries and source-isolated offline data. Windows Server 2022 run `34806098324` passed Release build, tests, portable packaging, checksum, and artifact upload for source commit `d43707a`. Its locally reverified package is being prepared as the unpublished `v0.1.0-windows-preview.3` draft. Real Windows-machine acceptance and deferred daily-use features remain mandatory before `PASS`.
- **Stage 15T: ACCEPTED** at `2578312`. The information-noise repair is merged and independently verified.
- **Stage 15S: ACCEPTED.** A real cancellation was previewed read-only against one exact current SIweb meeting, confirmed only after explicit action-time approval, and restored only after a separate undo approval. Audit, binding, and outbox evidence remained exact and scoped.
- **Stage 15R / 15: ACCEPTED.** The signed macOS `0.3.0 (4)` candidate passed live Canvas and SIweb reads, provider-boundary checks, UI evidence, automatic-cadence evidence, the dedicated-calendar lifecycle, and the post-Outlook-removal automated/build/signature gates.
- **Stage 10: PAUSED at 0/7.** Start only after the release candidate is accepted and frozen.
- **Outlook removed.** The product code, settings entry, tests, assessment, and former future Stage 13–14 plans are absent from the active repository; only immutable historical handoffs may still mention the abandoned integration.
- Latest accepted stage: **15**. Stage 16W is the authorized active coding stage; Stage 10 remains a separate opt-in seven-day trial.

## Git and implementation

- Branch `codex/windows-port`; Windows Preview 3 functional source commit `d43707a76c9125587e428004deb2e3110b7b99b0` passed run `34806098324`. The selected artifact id is `10334710441`, with Actions wrapper digest `sha256:61efd4dcd3b601df6acdbb6d9a748829f8ae7c9fcb27fd1ff09cf6e4dd4ae41f`; its inner portable ZIP digest is `sha256:d18b32e760a19acd4d81e0d07abfd884c3a15736a5e90b0db637c94ac99b2c7d`. Accepted macOS product baseline on `main` remains `776b2ef` (`Remove Outlook integration and finalize dashboard updates`).
- Frozen signed macOS candidate: version `0.3.0 (4)`, executable SHA-256 `d5ee7a4f549bf96cc5c14044351df8e19d3cc035259158ac9e2cea59d174d682`, bundle identifier `com.campusdashboard.desktop`, CDHash `71028af713336555023cab26bed328003ac78157`, ad-hoc signature. After Outlook removal it passes 239 tests across 20 suites, production build, app verification, strict signing, targeted safety scans, and signed-app UI checks. Today is a focused current-day summary; Schedule remains the full calendar grid.
- Announcements is the complete source feed. **待确认 / Needs Review** contains only unresolved actionable decisions; provider-unavailable and `other` results remain locally correctable, and resolved items leave the queue without disappearing from Announcements.
- Deterministically empty Canvas assignment shells remain in SQLite under stable identity, are collapsed by course, and are excluded from normal task surfaces, AI, Calendar, and notifications. A due date, meaningful instructions, attachment, quiz/external activity, meaningful submission route, or explicit offline/reading/preparation requirement reactivates the same item. Evidence uncertainty fails open to visibility. The local always-show override persists.
- Placeholder suppression/reactivation uses aggregate local counters only. Any time-saved figure must be explicitly formula-based and labeled as an estimate; synthetic results cannot support accuracy or resume claims.
- Stage 15S resolves cancellation targets only when course/section/meeting identity uniquely matches a current SIweb meeting. Ambiguous, stale, wrong-section, targetless, or response-deadline signals stay pending and cannot reach Schedule, Calendar, or notifications. Make-up classes use a separate app-owned event path. Every inferred date still requires explicit confirmation.
- The selected dedicated calendar is a valid user-selected iCloud calendar. On 2026-09-08 the user explicitly restored full Calendar access and authorized delivery of the eight queued reconciliation items. Duplicate Launch Services registrations for three preserved worktree app copies were removed, the current production app was reauthorized, and all eight items completed (`92` Calendar outbox rows completed, `0` pending). Two stale local binding rows for the old calendar identity were removed so their course meetings could be recreated in the current iCloud calendar; no old Calendar event was deleted or modified. The live app now reports `Dedicated calendar verified in iCloud`; iPhone arrival timing is controlled by iCloud.
- On 2026-09-12 the user accepted a real exact cancellation preview for one current SIweb meeting, separately approved the Calendar mutation, and separately approved undo. The final signal is `undone/resolved`, the exact target binding is restored and synced, and the Calendar outbox remains `97 completed / 0 pending`.
- After the user refreshed the authorized SIweb session on 2026-09-12, the signed executable passed aggregate-only live reads: Canvas `6 courses / 7 tasks / 10 announcements`; SIweb `92 meetings / 0 cancelled`. No school-system write was attempted.
- This build is ad-hoc signed because no developer signing identity is installed. Rebuilding changes its macOS code requirement and can require Calendar reauthorization again; durable distribution should use a stable Developer ID signature.

## Stable decisions

- Canvas API and SIweb access are authorized read-only. Never submit/change school data or bypass login, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Credentials, keys, cookies, tokens, and passwords are Keychain/user-entry only and never enter source, DB, config, fixtures, logs, screenshots, diagnostics, commands, commits, or handoffs.
- DeepSeek is opt-in and receives only minimum sanitized Canvas content. Do not modify FlClash/system proxy. Corrections stay local and are not uploaded as provider training data.
- Official source fields win. Every text-inferred date requires explicit confirmation before Calendar or deadline-notification eligibility, regardless of confidence.
- Calendar writes are limited to bound app-owned events in the dedicated Campus Dashboard calendar. Never touch personal, family, shared, subscribed, or unrelated events.
- Mailbox integration is not part of the product. Do not reintroduce OAuth registration, Graph/mail access, scraping, or mailbox-to-DeepSeek transfer without a new main-conversation scope and school-policy review.
- The Windows distribution has no iCloud or external-calendar integration. It retains the internal Today and Schedule experience and must not substitute Outlook, Microsoft Graph, Google Calendar, or CalDAV.
- Windows secrets use Windows Credential Manager or DPAPI-backed storage; macOS secrets remain in Keychain. Neither platform stores secrets in the database, configuration, logs, screenshots, commands, commits, or handoffs.

## Next gated work

1. Create and independently inspect the `v0.1.0-windows-preview.3` prerelease draft from the exact run `34806098324` assets; keep it private until fresh immediate publication confirmation.
2. After publication confirmation, ask the user or their friend to complete the real Windows launch, restart, Canvas and SIweb read-only sync, independent forget-source behavior, navigation, scaling, keyboard, localization, foreground-reminder, offline, clear-data, and privacy smoke matrix.
3. Return defects to Stage 16W and continue the remaining DeepSeek, complete shared persistence, native/background reminders, signed installer, and physical-machine accessibility work before daily-use acceptance.
4. Keep Stage 10 paused at 0/7 until the user separately asks to start the trial.

Stage 16W work is authorized only within the approved Windows plan. No real EventKit mutation is authorized without a fresh exact preview and action-time approval.

## Verification commands

The combined automated and real macOS acceptance gates have passed. If product code changes, rerun:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
git diff --check
```

Documentation-only changes do not require rebuilding the accepted app. Preserve the signed artifact identity above.

## Lightweight continuation

For Windows review or later work, read only `AGENTS.md`, this file, `.agent/stages/stage-16w.md`, `.agent/handoffs/stage-16w.md`, and `docs/windows-adaptation-review.md`. Do not read all handoffs, the full specification, removed-mailbox history, or the historical prompt collection.
