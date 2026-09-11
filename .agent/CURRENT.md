# Campus Dashboard current context

Updated: 2026-09-11 Asia/Macau.

## Active state

- **Stage 15T: ACCEPTED** at `2578312`. The information-noise repair is merged and independently verified.
- **Stage 15S: PARTIAL.** Implementation and correction/make-up workflows are merged through `f3c967c`; the remaining gate is a real exact cancellation preview followed by separately approved confirm and undo operations in the dedicated Campus Dashboard calendar.
- **Stage 15R / 15: PARTIAL.** Technical work is preserved. Acceptance and release freeze require the Stage 15S real Calendar gate plus a combined real signed-app Canvas/SIweb/UI check.
- **Stage 10: PAUSED at 0/7.** Start only after the release candidate is accepted and frozen.
- **Outlook removed.** The product code, settings entry, tests, assessment, and former future Stage 13–14 plans are absent from the active repository; only immutable historical handoffs may still mention the abandoned integration.
- Latest accepted stage: **15T**. No new coding stage is authorized; the next activity is the user-assisted Stage 15S real lifecycle acceptance gate.

## Git and implementation

- Branch `main`; Stage 15T product/tests/handoff commit: `2578312`. Main-thread acceptance is recorded in the current control commit.
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

## Remaining gate and next task

1. In the signed app, sync the authorized real Canvas and SIweb sources and confirm the combined task, announcement, Needs Review, placeholder, and schedule presentation remains coherent. Do not expose source text in logs or handoffs.
2. Locate the exact real cancellation case and inspect the read-only preview. It must identify the intended current SIweb meeting and proposed operation; unresolved/ambiguous cases must remain pending.
3. Only after the user gives fresh approval for that exact preview, confirm the dedicated-calendar mutation. Obtain separate fresh approval before undoing it. Verify Mac Calendar and iPhone iCloud create/update/removal behavior, stable identity, no duplicate, and no unrelated-event changes.
4. Record privacy-safe evidence in `.agent/handoffs/stage-15s.md`. Then the main conversation decides Stage 15S, Stage 15R, and Stage 15 acceptance and whether to freeze the build.
5. After freeze, revalidate setup and begin Stage 10 Day 1 on the next complete Asia/Macau day. The current trial remains 0/7.

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

Read only `AGENTS.md`, this file, `.agent/stages/stage-15s.md`, and the “Decision and remaining gate” plus “Required local user/administrator actions” ranges of `.agent/handoffs/stage-15s.md`, located first with `rg -n`. Read `.agent/handoffs/stage-15t.md` only if a concrete Stage 15T regression or evidence gap appears. Do not read all handoffs, the full specification, removed-mailbox history, or the historical prompt collection.
