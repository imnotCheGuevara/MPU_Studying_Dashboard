# Stage 04 — SIweb read-only crawler

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-02.md

## Prerequisite gate

Stage 02 must be accepted and Stage 04 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 04 only: the authorized read-only school website/SIweb crawler for Campus Dashboard.

Implement the crawler behind the existing connector contract for the explicitly approved school pages: [SIWEB_BASE_URL / TARGET PAGE LIST]. It may reuse a user-established lawful session through the agreed secure mechanism, but must never bypass SSO, MFA, CAPTCHA, robots/access restrictions, or submit state-changing forms. Implement bounded request rate/concurrency, timeout and retry classification, session-expiry detection, redacted diagnostics, stable-ID derivation, structural-contract checks, and parser versioning. Parse courses, course codes, meeting start/end, locations, source links, and cancellation/status information where present.

Use synthetic or irreversibly sanitized saved HTML fixtures. Do not store login pages, cookies, tokens, or unrelated personal content.

Acceptance:
- Parser tests cover normal pages, empty data, multiple meetings, timezone/date edge cases, cancelled classes, missing optional fields, expired session, login redirect, partial response, and changed DOM.
- Changed DOM stops import and reports a structural-change error rather than emitting guessed data.
- Repeated parsing/upsert is idempotent.
- Network layer proves it uses only allowed read methods/routes and respects configured limits.
- The production URLSession transport must disable automatic HTTP redirects. A redirect response must be returned to the connector and classified before any follow-up request is sent; add a transport-level regression test that would fail if URLSession follows the redirect or forwards the session Cookie to its destination.
- Production code, connection assessment, tests, and handoff must consistently identify the actual approved canonical crawler origin/path. If MPU's published `mpu.edu.mo` entry redirects to the operational `ipm.edu.mo` SIweb host, document that distinction without claiming both are the crawler target.
- Do not change the project-wide default hourly target cadence. Stage 04 implements no scheduler; scheduling remains owned by Stage 07.
- A real read-only smoke test on the approved target is mandatory for PASS and must not capture secrets/private bodies in the handoff; otherwise mark PARTIAL.

Write .agent/handoffs/stage-04.md. Do not implement Canvas, global sync orchestration, calendar, notifications, or AI.
