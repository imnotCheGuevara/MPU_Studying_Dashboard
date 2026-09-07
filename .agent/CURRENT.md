# Campus Dashboard current context

Updated: 2026-09-07 Asia/Macau.

## Active state

- **Stage 15S: IN PROGRESS.** The Stage 15R signed-app walkthrough found a release-blocking real defect: a Canvas 311/312 cancellation containing multiple weekday/date roles was inferred as a standalone Friday event instead of targeting the user's mapped Monday SIweb meeting. The active signal is `confirmed + no_target`; audit records a confirm transition, while later reconciliation can clear its target without revoking Calendar eligibility or returning it to review. Stage 15S must repair section/date-role targeting, stale-confirmation safety, correction UX, and Calendar projection before Stage 15R can pass.
- **Stage 15R: PARTIAL.** SIweb in-app authorization now closes correctly and immediately runs exactly one isolated successful SIweb sync (98 records); Canvas remains ready and the former 35-second loop did not recur. Calendar access is restored to the dedicated iCloud calendar. Final acceptance is blocked by Stage 15S and then a user-confirmed real Calendar lifecycle.
- **Stage 15: PARTIAL.** Its technical work is preserved: 213 tests passed, the synthetic classifier fixture improved from 17/20 to 20/20, the signed bundle built/launched, and live Canvas read-only smoke passed. It is not accepted because setup/recovery and mandatory real signed-app lifecycle checks remain incomplete.
- **Stage 10: PAUSED at 0/7.** Resume only after Stage 15R passes and the main conversation freezes the new candidate.
- **Stages 13–14: PAUSED/DEFERRED.** Outlook is outside this release pending school IT policy.
- Latest accepted stage: **12**. Direct current evidence: `.agent/handoffs/stage-15r.md`; active contract: `.agent/stages/stage-15s.md`.

## Git

- Branch `main`; latest Stage 15R repair commits are `7a6c8d5` and `387af8e`; main-control Stage 15S authorization edits are pending commit.
- Current candidate is `0.3.0 (4)`, executable SHA-256 `60402081d9ed538d24a7d682e480216d5d527ca4fe8fa088f14c91b880375c89`, CDHash `e6a68ab28caf0124e4884cca25f0ba167f95c41f`. It is not frozen and is superseded for repair by Stage 15S.

## Stable boundaries

- Canvas API and SIweb are authorized read-only. Never submit or change school data or bypass login, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Credentials, keys, cookies, tokens, and system passwords are Keychain/user-entry only. They never enter source, databases, configuration, fixtures, logs, screenshots, diagnostics, commands, commits, or handoffs. System prompts are completed only by the user.
- DeepSeek is opt-in and receives only minimum sanitized Canvas content. Direct HTTPS is exact-host `api.deepseek.com`; never change FlClash or the global/system proxy. Corrections are local, auditable, reversible supervised feedback and never uploaded as training data.
- Official dates are authoritative. Every text-inferred date requires explicit confirmation before Calendar or deadline-notification eligibility, regardless of confidence.
- Apple Calendar writes are limited to app-owned bound events in the dedicated Campus Dashboard calendar. Never touch personal, family, shared, subscribed, or unrelated events.
- Outlook remains disabled, unconfigured, dormant, and excluded. No app registration, authorization, Graph/mail access, scraping, or Outlook-to-DeepSeek transfer.

## Existing implementation

Swift/SwiftUI macOS app with SQLite, Keychain, read-only Canvas/SIweb connectors, isolated sync, EventKit, notifications/background scheduling, diagnostics, bilingual spatial calendars, controlled DeepSeek announcement classification, correction/personalization, schedule/exam mapping, confirmation gating, and signed `dist/Campus Dashboard.app`.

Stage 15R added the persistent setup checklist, in-app non-persistent SIweb authorization, isolated recovery center, centralized AI review/correction states, Calendar impact preview with confirmation/undo, accessible exam/deadline markers, local aggregate measurement, and disabled Outlook production entry.

The 2026-09-07 repair adds persistent Canvas↔SIweb mapping decisions and audit, unique high-confidence auto-mapping, explicit Map/Keep separate/Undo/Reset for code conflicts, canonical dashboard/filter/notification identities, local re-resolution of schedule-change signals, distinct non-deadline schedule-change presentation, and production filtering of `Stage10Test`/synthetic provenance without deleting stored rows.

## Stage 15S objective

1. Resolve multi-section schedule-change text using the confirmed course mapping, local section, semantic date role, and SIweb meeting candidates.
2. Never render or write an unresolved schedule change as a standalone confirmed event.
3. Return stale `confirmed + no_target` states to visible, correctable, Calendar-ineligible review without deleting source history.
4. Require an exact Calendar preview and explicit user confirmation regardless of confidence.
5. Preserve correction learning, exam styling, privacy, Outlook dormancy, and dedicated-calendar ownership.

Do not begin the seven-day trial or claim resume metrics. Do not perform a real EventKit mutation without action-time confirmation from the user in the main conversation. Stage 15R remains blocked until Stage 15S passes and the repaired real lifecycle is revalidated.

## Required final gate

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
git diff --check
```

Also run focused setup/recovery/AI/Calendar tests, bilingual signed-app and accessibility walkthrough, credential/private-data/prohibited-network scans, Outlook no-traffic assertion, and permitted aggregate-only real checks. Never handle user credentials; pause at macOS or institutional prompts for the user.

## Lightweight continuation

Read only `AGENTS.md`, `.agent/CURRENT.md`, `.agent/stages/stage-15s.md`, and the directly relevant sections of `.agent/handoffs/stage-15r.md`. Use targeted `rg -n` and narrow `sed -n` only for a named gap. Do not read Outlook history, all handoffs, the full specification, or old prompt collection. Stage task writes scoped product/tests and `.agent/handoffs/stage-15s.md`; central control files remain main-thread owned.
