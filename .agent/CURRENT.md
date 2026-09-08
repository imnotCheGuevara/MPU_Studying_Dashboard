# Campus Dashboard current context

Updated: 2026-09-08 Asia/Macau.

## Active state

- **Stage 15T: IN PROGRESS.** Authorized pre-release repair for information noise: Announcements remains the complete source feed; the renamed 待确认 / Needs Review center shows only unresolved actionable decisions; deterministic empty Canvas assignment shells are collapsed locally and reactivate when real work appears.
- **Stage 15S: PARTIAL.** Implementation and follow-up correction/make-up workflows are merged through `f3c967c`; all 244 tests pass. A real exact cancellation preview plus separately approved confirm/undo in the dedicated calendar remains mandatory.
- **Stage 15R / 15: PARTIAL.** Technical work is preserved; neither is accepted until 15T is accepted and the combined signed candidate completes the remaining real lifecycle gates.
- **Stage 10: PAUSED at 0/7.** Do not start the trial until the no-Outlook candidate is accepted and frozen.
- **Stages 13–14: PAUSED/DEFERRED.** Outlook remains outside this release pending school IT policy.
- Latest accepted stage: **12**. Current contract: `.agent/stages/stage-15t.md`; direct prerequisite evidence: relevant sections of `.agent/handoffs/stage-15s.md`.

## Git and implementation

- Branch `main`; Stage 15S correction workflows are committed at `f3c967c`. Stage 15T control files are the next main-thread commit.
- Swift/SwiftUI macOS app using SQLite, Keychain, read-only Canvas/SIweb connectors, isolated sync, EventKit, notifications/background scheduling, bilingual spatial calendars, and controlled DeepSeek announcement classification/correction.
- Current signed candidate is version `0.3.0 (4)`, but must be rebuilt after Stage 15T and must not be frozen yet.
- Stage 15S rejects schedule dates unless course/section/meeting identity resolves uniquely to a current SIweb meeting. Ambiguous, wrong-section, stale, targetless, or response-deadline signals remain pending and cannot reach Schedule, Calendar, or notifications. `makeup_class` is a separate app-owned event path; both paths require read-only preview and explicit confirmation.

## Stable decisions

- Canvas API and SIweb access are authorized read-only. Never submit/change school data or bypass login, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Credentials, keys, cookies, tokens, and passwords are Keychain/user-entry only and never enter source, DB, config, fixtures, logs, screenshots, diagnostics, commands, commits, or handoffs.
- DeepSeek is opt-in and receives only minimum sanitized Canvas content. Do not modify FlClash/system proxy. Corrections stay local and are not uploaded as training data.
- Official source fields win. Every text-inferred date requires explicit confirmation before Calendar or deadline-notification eligibility, regardless of confidence.
- Calendar writes are limited to bound app-owned events in the dedicated Campus Dashboard calendar. Never touch personal, family, shared, subscribed, or unrelated events.
- Outlook stays disabled, unconfigured, dormant, and excluded; no registration, authorization, Graph/mail access, scraping, or Outlook-to-DeepSeek transfer.

## Stage 15T outcome required

1. Announcements keeps all original items and source actions; Needs Review contains only unresolved actionable items and offers working correction for provider-unavailable and `other` cases.
2. Truly empty Canvas assignment shells are preserved but collapsed per course, excluded from AI/Calendar/notifications/normal task lists, and safely reactivated under the same stable identity when any actionable source evidence appears.
3. No-submission offline/reading tasks stay visible; uncertain evidence fails open. Persist user visibility override and aggregate-only suppression/reactivation metrics.
4. Preserve all Stage 15S safety gates and Outlook dormancy. Stage task writes only scoped code/tests and `.agent/handoffs/stage-15t.md`.

## Verification and next gate

Required final commands:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
git diff --check
```

Also require focused queue/placeholder/migration/downstream tests, bilingual synthetic signed-app and accessibility walkthrough, and targeted secret/private-data/network scans. No real EventKit mutation without fresh action-time approval.

After the Stage 15T task produces its handoff, the main conversation inspects the diff and handoff, reruns high-risk checks, and either accepts or returns a bounded repair. Only after 15T acceptance should the combined real Canvas/SIweb/UI lifecycle and the outstanding Stage 15S Calendar gate be resumed.

## Lightweight continuation

Read only `AGENTS.md`, this file, `.agent/stages/stage-15t.md`, and relevant sections of `.agent/handoffs/stage-15s.md` located with `rg -n`. Do not read all handoffs, the full specification, Outlook history, or the old prompt collection unless a concrete gap requires a narrow lookup.
