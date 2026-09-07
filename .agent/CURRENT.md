# Campus Dashboard current context

Updated: 2026-09-07 Asia/Macau.

## Active state

- **Stage 15R: PARTIAL / user-permission walkthrough pending.** Reconciliation commits `5df93d7` and `bcadf8f` add deterministic matching, conflict decisions, canonical courses, correct schedule-change semantics, and synthetic-source filtering; 226 tests/20 suites pass. The real database still has 6 Canvas + 6 SIweb courses and no materialized mappings because the rebuilt app is waiting at a user-only Keychain/system-permission boundary. Acceptance requires unlocking it, restoring dedicated Calendar access, then checking the real reconciliation UI and preview-only calendar lifecycle.
- **Stage 15: PARTIAL.** Its technical work is preserved: 213 tests passed, the synthetic classifier fixture improved from 17/20 to 20/20, the signed bundle built/launched, and live Canvas read-only smoke passed. It is not accepted because setup/recovery and mandatory real signed-app lifecycle checks remain incomplete.
- **Stage 10: PAUSED at 0/7.** Resume only after Stage 15R passes and the main conversation freezes the new candidate.
- **Stages 13–14: PAUSED/DEFERRED.** Outlook is outside this release pending school IT policy.
- Latest accepted stage: **12**. Direct current evidence: `.agent/handoffs/stage-15r.md`.

## Git

- Branch `main`; initial release baseline `b4d6f23fe56cf8f66ec8e4755230fd2be5e1bdc3`, reconciliation implementation `5df93d7`, handoff `bcadf8f`; only main-control status edits are pending commit.
- Current candidate: `0.3.0 (4)`, executable SHA-256 `5343b33a5aeca9c394dfcea6b42cb1696a347a514c7bc8ebc21ab49328034f90`, CDHash `f0c420420cd0726f53449a2a4db74a0cdf02724f`. It is not frozen until the real walkthrough passes.

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

## Stage 15R objective

1. Complete in-app setup for Canvas, SIweb, dedicated Calendar, notifications, and optional DeepSeek.
2. Actionable privacy-safe recovery for each supported failure category with subsystem isolation.
3. Centralized persistent/reversible AI review, correction and confirmation, including empty `other` and provider fallback.
4. Explicit Calendar create/update/cancel preview, confirmation/undo, idempotence, and accessible exam semantics.
5. Scanned reproducible initial Git/release baseline with build/signing/hash identity.
6. Privacy-safe real metrics instrumentation, keeping synthetic estimates separate from observed trial results.

Do not begin the seven-day trial or claim resume metrics yet. The user must complete the visible Keychain/system prompt and restore permission only for the dedicated Campus Dashboard calendar. Then inspect the real reconciliation controls, confirm that canonical course controls replace duplicates and synthetic sources are hidden, and verify a preview-before-write schedule-change lifecycle. Only main-thread acceptance may resume Stage 10.

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

Read only `AGENTS.md`, `.agent/CURRENT.md`, `.agent/stages/stage-15r.md`, and `.agent/handoffs/stage-15r.md`. Use targeted `rg -n` and narrow `sed -n` only for a named gap. Do not read Outlook history, all handoffs, the full specification, or old prompt collection. Stage task writes scoped product/tests and `.agent/handoffs/stage-15r.md`; central control files remain main-thread owned.
