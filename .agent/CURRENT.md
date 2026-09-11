# Campus Dashboard current context

Updated: 2026-09-11 Asia/Macau.

## Active state

- **Stage 16W: IN PROGRESS.** The user authorized a reusable Windows distribution. It keeps the accepted domain/source safety baseline, omits iCloud and all external-calendar integration, and will be delivered through a Windows CI artifact followed by a real Windows-machine smoke.
- **Stage 15T: ACCEPTED** at `2578312`. The information-noise repair is merged and independently verified.
- **Stage 15S: PARTIAL.** Implementation and correction/make-up workflows are merged through `f3c967c`; the remaining gate is a real exact cancellation preview followed by separately approved confirm and undo operations in the dedicated Campus Dashboard calendar.
- **Stage 15R / 15: PARTIAL.** Technical work is preserved. Acceptance and release freeze require the Stage 15S real Calendar gate plus a combined real signed-app Canvas/SIweb/UI check.
- **Stage 10: PAUSED at 0/7.** Start only after the release candidate is accepted and frozen.
- **Outlook removed.** The product code, settings entry, tests, assessment, and former future Stage 13–14 plans are absent from the active repository; only immutable historical handoffs may still mention the abandoned integration.
- Latest accepted stage: **15T**. The current authorized coding stage is **16W** on `codex/windows-port`; the macOS Stage 15S real lifecycle gate remains independently pending and is not authorized by Windows work.

## Git and implementation

- Branch `codex/windows-port`, based on `main`; Stage 15T product/tests/handoff commit: `2578312`.
- Current signed candidate version is `0.3.0 (4)`. After Outlook removal it passes 239 tests across 20 suites, production build, app verification, strict signing, targeted safety scans, and an isolated synthetic signed-app launch. Today is now a focused current-day summary, Schedule remains the full calendar grid, and Today uses confirmed/corrected schedule changes. It is not frozen yet.
- Announcements is the complete source feed. **待确认 / Needs Review** contains only unresolved actionable decisions; provider-unavailable and `other` results remain locally correctable, and resolved items leave the queue without disappearing from Announcements.
- Deterministically empty Canvas assignment shells remain in SQLite under stable identity, are collapsed by course, and are excluded from normal task surfaces, AI, Calendar, and notifications. A due date, meaningful instructions, attachment, quiz/external activity, meaningful submission route, or explicit offline/reading/preparation requirement reactivates the same item. Evidence uncertainty fails open to visibility. The local always-show override persists.
- Placeholder suppression/reactivation uses aggregate local counters only. Any time-saved figure must be explicitly formula-based and labeled as an estimate; synthetic results cannot support accuracy or resume claims.
- Stage 15S resolves cancellation targets only when course/section/meeting identity uniquely matches a current SIweb meeting. Ambiguous, stale, wrong-section, targetless, or response-deadline signals stay pending and cannot reach Schedule, Calendar, or notifications. Make-up classes use a separate app-owned event path. Every inferred date still requires explicit confirmation.
- The selected dedicated calendar is a valid user-selected iCloud calendar. On 2026-09-08 the user explicitly restored full Calendar access and authorized delivery of the eight queued reconciliation items. Duplicate Launch Services registrations for three preserved worktree app copies were removed, the current production app was reauthorized, and all eight items completed (`92` Calendar outbox rows completed, `0` pending). Two stale local binding rows for the old calendar identity were removed so their course meetings could be recreated in the current iCloud calendar; no old Calendar event was deleted or modified. The live app now reports `Dedicated calendar verified in iCloud`; iPhone arrival timing is controlled by iCloud.
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

## Active Windows work and preserved macOS gate

1. Build the smallest native Windows slice from the existing Swift domain and synthetic fixtures, then validate it on a clean GitHub Windows runner.
2. Extend only proven reusable boundaries to persistence, read-only connectors, AI consent/validation, notifications, localization, and packaging.
3. Publish a versioned Windows artifact for the user's separate Windows computer and close defects found in the real smoke.
4. Keep the following macOS acceptance work pending; Windows work does not perform or authorize it.

5. In the signed macOS app, sync the authorized real Canvas and SIweb sources and locate the exact real cancellation preview without exposing source text.
6. Only after fresh action-time approval, confirm and separately approve undo in the dedicated calendar; then record Stage 15S evidence and decide the macOS release gates.

No real EventKit mutation is authorized merely by opening or continuing a task. Fresh action-time approval is mandatory for each confirm and undo operation.

## Verification commands

The combined automated gate already passed at Stage 15T acceptance. If code changes before the real gate, rerun:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
git diff --check
```

For a no-code real acceptance session, do not repeat the full suite; verify the installed signed-app identity and record only concise, redacted lifecycle evidence.

## Lightweight continuation

For Windows work, read only `AGENTS.md`, this file, `.agent/stages/stage-16w.md`, and the most recent `.agent/handoffs/stage-16w.md` when it exists. For the preserved macOS gate, use the earlier Stage 15S continuation rule. Do not read all handoffs, the full specification, removed-mailbox history, or the historical prompt collection.
