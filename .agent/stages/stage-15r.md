# Stage 15R — Release usability closure

## Startup and ownership

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and `.agent/handoffs/stage-15.md`. Use targeted `rg -n` plus narrow `sed -n` only for a concrete gap. This task owns Stage 15R product implementation and `.agent/handoffs/stage-15r.md`; it must not edit central control files or begin the seven-day Stage 10 trial.

## Goal

Turn the signed no-Outlook release candidate into a self-contained, recoverable daily-use product. Close all six release standards approved by the user: in-app setup, actionable failure recovery, correctable/confirmable AI results, a verified Canvas/SIweb/DeepSeek/Calendar workflow, reproducible version control, and honest measurable trial instrumentation.

## Required implementation

1. **In-app setup.** Add a first-run/setup experience and Settings controls for Canvas, SIweb, the dedicated Campus Dashboard calendar, notifications, and optional DeepSeek. SIweb must expose Connect/Reauthorize in Settings and reuse the existing non-persistent institutional WebKit flow. Secrets remain Keychain-only and login fields remain owned by the institution/provider. Terminal-only setup is not acceptable for a normal user.
2. **Recovery model.** Give authentication expiry, missing consent/key, network/exact-host, HTTP/rate-limit, timeout, schema/decoding, budget, Calendar permission, and notification permission failures a privacy-safe category, unaffected-feature statement, and specific recovery action. Recovery must resume safely without deleting local history or duplicating writes.
3. **AI action center.** Provide a centralized review surface for pending, confirmed, corrected, conflict, provider-unavailable fallback, ignored, and Calendar-written results. Every result, including empty `other` and fallback results, must support local correction. Show provenance and allow preview, confirm, ignore, undo, reset, and course-local reversible personalization. Never claim unsupervised or remote model training.
4. **Calendar preview and semantics.** Before any inferred date becomes eligible, preview create/update/cancel, target dedicated calendar, course, event type, date/time, affected bound event, and undo effect. Course cancellation, makeup/change, assignment deadline, and exam must have distinct semantics. Exams require accessible in-app color plus label/icon and a non-color Apple Calendar marker. Repeat/update/undo must be idempotent and confined to app-owned bound events.
5. **Reproducible release baseline.** Because the repository currently has no valid `HEAD`, first run credential/private-payload/generated-artifact scans and inspect ignore rules. After all required checks pass, create the initial Git commit without rewriting or deleting history, record the commit, app SHA-256, signing identity/CDHash, exact build commands, and version in the handoff. Do not add secrets, local databases, session data, screenshots with private content, or disposable logs.
6. **Honest outcome measurement.** Add privacy-safe local aggregate instrumentation and a documented evaluation protocol for sync success, latency, AI per-class precision/recall/F1, critical-event miss rate, correction/fallback recovery rate, duplicates/unsafe writes, notification duplication, and observed user handling time. Keep synthetic estimates explicitly separate from observed seven-day results. Do not fabricate resume claims.

Outlook remains dormant, disabled, unconfigured, untested beyond a focused no-traffic assertion, and outside this release.

## Acceptance

- A normal user can complete or repair every supported integration from the signed app without Terminal; macOS credential/permission prompts are completed only by the user.
- The setup checklist persists, explains minimum data use, and never exposes secrets. Revocation and reauthorization preserve unrelated cached data unless the user explicitly clears it.
- Each enumerated failure category has tested actionable recovery and independent subsystem isolation.
- The AI review/correction lifecycle persists across restart, is auditable/reversible, and cannot bypass inferred-date confirmation.
- Fake-service end-to-end tests prove zero writes for ambiguity/unconfirmed inference and exactly-one idempotent bound-event behavior for confirmed schedule changes and exams.
- The complete automated suite, clean signed build, app verification, strict code-signing, privacy/security scans, bilingual UI checks, accessibility checks, and focused Outlook dormancy assertion pass.
- Available real read-only Canvas, SIweb, consented minimum-content DeepSeek, and existing-dedicated-calendar lifecycle checks pass with aggregate-only evidence. If a user-only authorization is required, stop at the prompt without handling credentials and record the exact remaining action; never mark `PASS` while it remains.
- A valid Git `HEAD` and frozen signed candidate are recorded only after the repository passes the secret/private-data scan.
- `.agent/handoffs/stage-15r.md` records changed files, commands and concise results, manual evidence, measurement definitions/baselines, release identity, and remaining seven-day risks. Use `PASS`, `PARTIAL`, or `BLOCKED` honestly.

## Required checks

Use focused tests during development, then run at the final gate:

```sh
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
git diff --check
```

Also run targeted credential/private-payload/prohibited-network scans, the new setup/recovery/correction/Calendar tests, bilingual signed-app walkthrough, and the aggregate-only real-service checks permitted above. Keep verbose output in temporary logs and report summaries only.
