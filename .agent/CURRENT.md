# Campus Dashboard current context

Updated: 2026-09-07 Asia/Macau.

## Active state

- **Stage 15R: PARTIAL / user authorization pending.** Implementation is complete: 219 tests in 19 suites, signed build/launch verification, privacy scans, Outlook dormancy, and the reproducible Git baseline pass. Acceptance still requires user-only Keychain approval, in-app SIweb authorization, dedicated Calendar permission, and the final real bilingual/accessibility and bound-event walkthrough.
- **Stage 15: PARTIAL.** Its technical work is preserved: 213 tests passed, the synthetic classifier fixture improved from 17/20 to 20/20, the signed bundle built/launched, and live Canvas read-only smoke passed. It is not accepted because setup/recovery and mandatory real signed-app lifecycle checks remain incomplete.
- **Stage 10: PAUSED at 0/7.** Resume only after Stage 15R passes and the main conversation freezes the new candidate.
- **Stages 13–14: PAUSED/DEFERRED.** Outlook is outside this release pending school IT policy.
- Latest accepted stage: **12**. Direct predecessor evidence for 15R: `.agent/handoffs/stage-15.md`.

## Git

- Branch `main`; initial release baseline `b4d6f23fe56cf8f66ec8e4755230fd2be5e1bdc3`, current clean `HEAD` `61d7d75`.
- Frozen candidate: `0.3.0 (4)`, executable SHA-256 `f242fba9918e3de51c980368b21cf76ef4a8828299c52d24dfd918d231109923`, CDHash `6ad7527a48729b35e4cf3a8d7ca3d25f0109609e`.

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

## Stage 15R objective

1. Complete in-app setup for Canvas, SIweb, dedicated Calendar, notifications, and optional DeepSeek.
2. Actionable privacy-safe recovery for each supported failure category with subsystem isolation.
3. Centralized persistent/reversible AI review, correction and confirmation, including empty `other` and provider fallback.
4. Explicit Calendar create/update/cancel preview, confirmation/undo, idempotence, and accessible exam semantics.
5. Scanned reproducible initial Git/release baseline with build/signing/hash identity.
6. Privacy-safe real metrics instrumentation, keeping synthetic estimates separate from observed trial results.

Do not begin the seven-day trial or claim resume metrics yet. The user must approve the existing app Keychain item, authorize SIweb from Settings, and restore permission only for the dedicated Campus Dashboard calendar. Then run the final aggregate-only real workflow checks. Only main-thread acceptance may resume Stage 10.

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

Read only `AGENTS.md`, `.agent/CURRENT.md`, `.agent/stages/stage-15r.md`, and `.agent/handoffs/stage-15.md`. Use targeted `rg -n` and narrow `sed -n` only for a named gap. Do not read Outlook history, all handoffs, the full specification, or old prompt collection. Stage task writes scoped product/tests and `.agent/handoffs/stage-15r.md`; central control files remain main-thread owned.
