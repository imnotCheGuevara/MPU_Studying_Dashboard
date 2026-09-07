# Stage 03 — Canvas API connector

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-02.md

## Prerequisite gate

Stage 02 must be accepted and Stage 03 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 03 only: the read-only Canvas API connector for Campus Dashboard.

Implement a read-only Canvas API connector using the existing service contracts. Support the approved authorization configuration through Keychain, pagination, rate-limit awareness, timeouts, retry classification, and redacted diagnostics. Fetch current-user courses, assignments including effective date overrides and quiz-like/New Quiz/LTI classification when exposed, and announcements. Convert API DTOs to connector records without putting Canvas DTOs into UI/domain layers. Use synthetic sanitized fixtures for deterministic tests.

Live values such as [CANVAS_BASE_URL] and authorization must be supplied locally through the app or a non-echoing secure mechanism; never request that credentials be pasted into chat and never print them.

Acceptance:
- Fixture tests cover pagination, assignments, effective due-date overrides, Classic/New/external-tool quiz-like items, announcements, undated items, malformed responses, 401/403/429/5xx, and redaction.
- Repeating the same fixture import creates no duplicates.
- Connector performs no Canvas write request.
- Connector concurrency is explicitly bounded with a cancellation-safe gate and a controlled concurrent-request test; actor isolation alone is not accepted as a concurrency bound because actor methods are reentrant across `await`.
- Retry without `Retry-After` uses bounded exponential backoff with injected/testable jitter, as required by the project specification.
- Canvas `has_overrides` must not be represented as proof that the current user's effective date was overridden. Preserve the effective `due_at` supplied for the requesting user and name any override metadata according to its actual Canvas semantics. Do not claim `all_dates` is retained unless it is decoded and carried across the connector boundary.
- If local authorization and endpoint are available, perform and document a minimal read-only smoke test without recording private response bodies. This real smoke test is mandatory for PASS; otherwise mark PARTIAL and state the single remaining action.
- If any authorization value was ever visible in terminal output, a screenshot, log, or task message, that credential must be revoked at Canvas and replaced before PASS. The handoff must record user confirmation of revocation/rotation without recording the credential.

Write .agent/handoffs/stage-03.md. Do not implement the SIweb crawler, global sync orchestration, calendar, notifications, or AI.
