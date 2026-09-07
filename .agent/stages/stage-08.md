# Stage 08 — AI parsing and confirmation queue

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-07.md; earlier direct prerequisites are summarized in CURRENT.md.

## Prerequisite gate

Stages 05, 06, and 07 must be accepted and Stage 08 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 08 only: controlled AI-assisted Canvas organization and the human confirmation queue.

Implement deterministic-rule-first processing, a provider-neutral AI interface, strict structured-output validation, minimal input construction, parse provenance, confidence/reason storage, conflict flags, related-item suggestions, short change summaries, and the confirmation UI/workflow. External AI remains off by default until provider disclosure and consent exist; provide a deterministic fake provider for tests. Confirmation, correction, rejection, and undo must be auditable. AI may suggest but never directly invoke a connector, EventKit, or notifications.

Acceptance:
- Tests prove official dates are immutable and take precedence.
- Every text-derived date is marked inferred regardless of confidence.
- Calendar and deadline notification boundaries reject unconfirmed inference.
- Invalid/malformed AI output fails safely and does not block normal sync.
- Duplicate suggestions never delete or physically merge source records.
- Disabling AI leaves all deterministic functionality usable.
- A synthetic evaluation set reports classification, duplicate-suggestion, date-extraction, and uncertainty metrics; unauthorized calendar/notification writes must be zero.

Write .agent/handoffs/stage-08.md. Do not expand into Phase 2 study planning.
