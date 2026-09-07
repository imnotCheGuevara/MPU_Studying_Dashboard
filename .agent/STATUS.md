# Main-thread stage status

Only the main project conversation updates this file after inspecting and accepting a stage handoff.

Current authorized stage: **Stage 15S**

| Stage | Status | Accepted handoff | Notes |
| --- | --- | --- | --- |
| 01 | ACCEPTED | `.agent/handoffs/stage-01.md` | Build, 9 tests, scope scan, and native launch independently verified by main conversation |
| 02 | ACCEPTED | `.agent/handoffs/stage-02.md` | 23 tests, versioned SQLite, Keychain lifecycle, signed `.app`, sandbox DB, and scope/security scans independently verified |
| 03 | ACCEPTED | `.agent/handoffs/stage-03.md` | 36 tests, cancellation-safe concurrency gate, jittered retry, corrected override semantics, signed-app read-only smoke, and credential scans independently verified; user confirmed the exposed old Canvas token was revoked and replaced |
| 04 | ACCEPTED | `.agent/handoffs/stage-04.md` | 58 tests, production redirect refusal with loopback proof, GET-only allowlist, Keychain session boundary, fail-closed parsing, signed-app live smoke (92 meetings), endpoint documentation, and security scans independently verified |
| 05 | ACCEPTED | `.agent/handoffs/stage-05.md` | 78 tests, transactional normalization/outbox, source isolation, deletion evidence, persistent per-family baselines, timestamp-free announcement idempotency, migration v3, signing, and scope/security scans independently verified |
| 06 | ACCEPTED | `.agent/handoffs/stage-06.md` | 93 tests, scoped EventKit external-ID recovery, binding repair, fail-closed ambiguity handling, dedicated-calendar isolation, signed app, and real-Mac iCloud-source create/update/repeat/cancel smoke independently verified |
| 07 | ACCEPTED | `.agent/handoffs/stage-07.md` | 111 tests, deterministic notification/outbox behavior, quiet-hours and DST handling, failure/recovery suppression, user-controlled background scheduling, signed app, real login-item smoke, and real authorized pending-to-delivered notification smoke independently verified |
| 08 | ACCEPTED | `.agent/handoffs/stage-08.md` | 22 AI tests and 134-test full suite pass; awaited confirm/correct/undo notification reconciliation, durable Calendar desired-state repair, strict provider bounds, signed app, security scans, and UI checks evidenced; main conversation independently re-ran the 134-test suite and debug build |
| 09 | ACCEPTED | `.agent/handoffs/stage-09.md` | 143-test end-to-end suite, privacy/category isolation, separately previewed Calendar cleanup, redacted diagnostics, accessibility/keyboard checks, signed app, and responsiveness evidence accepted; main conversation independently re-ran tests, release build, launch/Keychain smoke, signing, plist, credential, and diagnostic-field scans |
| 10R | ACCEPTED | `.agent/handoffs/stage-10r.md` | 164-test suite, weekly timetable/overlap layout, spatial day/week/month Schedule, unread-announcement sidebar, English/Simplified Chinese coverage, source-text preservation, signed app, security scans, and required window-size QA accepted; main conversation independently re-ran tests/build/signing and inspected English/Chinese Today, week Schedule, and month Schedule |
| 10 | PAUSED | `.agent/handoffs/stage-10.md` (`PARTIAL`) | Remains at 0/7 until Stage 15R closes the six release-usability standards and the no-Outlook candidate is accepted and frozen; then revalidate setup and start Day 1 on the next complete Asia/Macau day |
| 11 | ACCEPTED | `.agent/handoffs/stage-11.md` | 181-test suite, exact-host direct-routing safety, Debug/Release/signing/scans, bilingual disclosure, and unchanged-bundle real DeepSeek smoke accepted; main conversation independently re-ran the 181-test suite and verified signature, SHA-256, CDHash, and absence of global-proxy APIs/SystemConfiguration linkage |
| 12 | ACCEPTED | `.agent/handoffs/stage-12.md` | 196-test suite, four-class multilingual evaluation, strict v3 real DeepSeek announcement validation, pending-date confirmation isolation, bilingual isolated signed-app UI/AX QA, signing and scans accepted; main conversation independently re-ran all 196 tests and verified signature and final SHA-256 |
| 13 | PAUSED | `.agent/handoffs/stage-13.md` (`PARTIAL`) | Outlook is deferred outside the active release path pending school IT guidance. Offline implementation remains preserved; no registration, authorization, token, tenant smoke, or mail sync is permitted |
| 14 | DEFERRED | — | Outlook-only implementation is outside the active release path and cannot start while Stage 13 is paused |
| 15 | PARTIAL | `.agent/handoffs/stage-15.md` (`PARTIAL`) | Technical integration candidate delivered, but terminal-only SIweb authorization and incomplete setup/recovery/real lifecycle prevent release acceptance; superseded for repair by Stage 15R |
| 15R | PARTIAL | `.agent/handoffs/stage-15r.md` (`PARTIAL`) | Reconciliation repair committed (`5df93d7`, handoff `bcadf8f`); 226 tests/20 suites, build, signature, safety scans, conflict decisions, canonical presentation, schedule-change semantics, and synthetic-source exclusion pass. Awaiting the user-only Keychain/system prompt, dedicated Calendar permission, and main-thread real signed-app walkthrough before acceptance |
| 15S | IN PROGRESS | `.agent/handoffs/stage-15s.md` | Release-blocking real defect: a multi-section cancellation selected the wrong weekday, failed to bind the matching SIweb meeting, and remained displayed as confirmed after its target was lost. Repair must restore explicit confirmation and Calendar safety before Stage 15R can be accepted. |

Status meanings:

- `LOCKED`: prerequisites are not accepted.
- `READY`: main conversation authorizes a stage task to begin.
- `IN PROGRESS`: a stage task is working.
- `PAUSED`: an authorized stage is deliberately suspended behind a newly introduced acceptance gate; it cannot accumulate completion credit until resumed by the main conversation.
- `DEFERRED`: the stage is preserved for a later roadmap decision but is outside the current release path and cannot start.
- `REVIEW`: a handoff exists and awaits main-conversation acceptance.
- `ACCEPTED`: main conversation verified and accepted the stage.
- `BLOCKED`: mandatory external input or action prevents completion.
