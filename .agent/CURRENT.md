# Campus Dashboard current context

Updated: 2026-09-08 Asia/Macau.

## Active state

- **Stage 15S: PARTIAL.** Repairs are merged at `8a9e8b7`; the main conversation passed 63 focused tests, relaunched the signed app, verified schema 14, confirmed source `25573` is pending/no-target, opened its correction UI, and observed no standalone Friday entry. Its stored legacy date remains wrong, so a consented reprocess or user correction plus exact preview/confirm/undo remains mandatory.
- **Stage 15R: PARTIAL.** SIweb in-app authorization now closes correctly and immediately runs exactly one isolated successful SIweb sync (98 records); Canvas remains ready and the former 35-second loop did not recur. Calendar access is restored to the dedicated iCloud calendar. Final acceptance is blocked by Stage 15S and then a user-confirmed real Calendar lifecycle.
- **Stage 15: PARTIAL.** Its technical work is preserved: 213 tests passed, the synthetic classifier fixture improved from 17/20 to 20/20, the signed bundle built/launched, and live Canvas read-only smoke passed. It is not accepted because setup/recovery and mandatory real signed-app lifecycle checks remain incomplete.
- **Stage 10: PAUSED at 0/7.** Resume only after Stage 15R passes and the main conversation freezes the new candidate.
- **Stages 13–14: PAUSED/DEFERRED.** Outlook is outside this release pending school IT policy.
- Latest accepted stage: **12**. Direct current evidence: `.agent/handoffs/stage-15s.md`; active contract: `.agent/stages/stage-15s.md`.

## Git

- Branch `main`; Stage 15S implementation is merged at `8a9e8b7` on top of authorization commit `5ad3a0b`.
- Main-checkout rebuilt candidate is `0.3.0 (4)`, executable SHA-256 `4e8cd14e636688430476d6d18db36c00060ce00b8621dba97b9697b02d51599e`; strict signature verification passed. Do not freeze it until the remaining real gates pass.

## Stable boundaries

- Canvas API and SIweb are authorized read-only. Never submit or change school data or bypass login, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Credentials, keys, cookies, tokens, and system passwords are Keychain/user-entry only. They never enter source, databases, configuration, fixtures, logs, screenshots, diagnostics, commands, commits, or handoffs. System prompts are completed only by the user.
- DeepSeek is opt-in and receives only minimum sanitized Canvas content. Direct HTTPS is exact-host `api.deepseek.com`; never change FlClash or the global/system proxy. Corrections are local, auditable, reversible supervised feedback and never uploaded as training data.
- Official dates are authoritative. Every text-inferred date requires explicit confirmation before Calendar or deadline-notification eligibility, regardless of confidence.
- Apple Calendar writes are limited to app-owned bound events in the dedicated Campus Dashboard calendar. Never touch personal, family, shared, subscribed, or unrelated events.
- Outlook remains disabled, unconfigured, dormant, and excluded. No app registration, authorization, Graph/mail access, scraping, or Outlook-to-DeepSeek transfer.

## Existing implementation

Swift/SwiftUI macOS app with SQLite, Keychain, read-only Canvas/SIweb connectors, isolated sync, EventKit, notifications/background scheduling, diagnostics, bilingual spatial calendars, controlled DeepSeek announcement classification, correction/personalization, schedule/exam mapping, confirmation gating, and signed `dist/Campus Dashboard.app`.

Stage 15R added in-app setup/recovery, audited Canvas↔SIweb mapping, centralized AI correction, exact Calendar preview/confirmation/undo, exam/deadline markers, aggregate metrics, synthetic-data filtering, and a disabled Outlook entry.

Stage 15S now rejects provider dates unless the affected meeting role, enrolled SIweb section, proposed meeting identity, persisted target, and current unique SIweb meeting agree. Ambiguous, wrong-section, make-up, response-deadline, stale, or targetless schedule changes return to pending review and are excluded from Schedule, Calendar, and notifications. Manual correction saves only a pending proposal; a fresh exact preview and separate confirmation are required.

## Stage 15S remaining gate

1. Complete signed-app Canvas and SIweb read-only refreshes without exposing source content.
2. Reprocess source `25573` with explicit DeepSeek data-transfer consent, or let the user correct it to the exact September 7 SIweb meeting.
3. Verify the resulting exact bilingual preview.
4. After fresh action-time approval, confirm and undo only that previewed meeting in the dedicated Campus Dashboard calendar.

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
