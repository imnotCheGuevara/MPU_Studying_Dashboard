# Campus Dashboard current context

Updated: 2026-09-12 Asia/Macau.

## Active state

- **Stage 16W: PAUSED — AWAITING USER REVIEW.** Two earlier draft commits (`101e014`, `40f30f0`) are preserved on `codex/windows-port` as unreviewed work. Do not change implementation, CI configuration, packaging, or distribution until the user approves `docs/windows-adaptation-review.md`. An existing workflow may run automatically after documentation pushes; that does not count as acceptance or authorize fixes.
- **Stage 15T: ACCEPTED** at `2578312`. The information-noise repair is merged and independently verified.
- **Stage 15S: ACCEPTED.** A real cancellation was previewed read-only against one exact current SIweb meeting, confirmed only after explicit action-time approval, and restored only after a separate undo approval. Audit, binding, and outbox evidence remained exact and scoped.
- **Stage 15R / 15: ACCEPTED.** The signed macOS `0.3.0 (4)` candidate passed live Canvas and SIweb reads, provider-boundary checks, UI evidence, automatic-cadence evidence, the dedicated-calendar lifecycle, and the post-Outlook-removal automated/build/signature gates.
- **Stage 10: PAUSED at 0/7.** Start only after the release candidate is accepted and frozen.
- **Outlook removed.** The product code, settings entry, tests, assessment, and former future Stage 13–14 plans are absent from the active repository; only immutable historical handoffs may still mention the abandoned integration.
- Latest accepted stage: **15**. There is no authorized coding stage. The next action is user review of the Windows adaptation proposal; Stage 10 remains a separate opt-in seven-day trial.

## Git and implementation

- Branch `codex/windows-port`; accepted macOS product baseline on `main`: `776b2ef` (`Remove Outlook integration and finalize dashboard updates`). The branch also contains the earlier unreviewed Windows draft commits `101e014` and `40f30f0`. They remain preserved but unaccepted; the review-gate commit changes documentation only.
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

1. Give the user `docs/windows-adaptation-review.md` for review.
2. Make requested documentation changes without touching the preserved Windows draft.
3. Resume Stage 16W only after explicit approval. Then prove the smallest native Windows slice in a clean Windows runner before extending persistence, read-only connectors, credential protection, reminders, localization, and packaging.
4. Keep Stage 10 paused at 0/7 until the user separately asks to start the trial.

No Windows implementation is authorized by opening or continuing a task while Stage 16W is paused. No real EventKit mutation is authorized without a fresh exact preview and action-time approval.

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
