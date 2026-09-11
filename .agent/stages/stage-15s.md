# Stage 15S — Schedule-change targeting and confirmation safety repair

## Startup and ownership

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and `.agent/handoffs/stage-15r.md` sections concerning AI review, course reconciliation, Calendar preview, and remaining gates. Locate those sections with `rg -n` before a narrow `sed -n` read. This task owns only the product/tests needed for Stage 15S and `.agent/handoffs/stage-15s.md`; it must not edit central control files or begin Stage 10.

## Goal

Repair the release-blocking real case where a Canvas announcement for sections 311/312 contains more than one weekday/date, but a cancellation for the user's section is projected as a standalone event on the wrong day instead of being associated with the matching SIweb class meeting. Restore the non-negotiable rule that every text-inferred date and every schedule-change Calendar effect requires an explicit user confirmation.

## Required implementation

- Keep Canvas and SIweb source records immutable and read-only. Use the confirmed Canvas↔SIweb course mapping and the user's local section plus SIweb meeting candidates as hard constraints.
- For schedule changes, distinguish the affected/cancelled meeting from makeup options, response deadlines, and dates for other sections. Never select a date merely because it is the last or most salient date in the text.
- Validate any provider date against the eligible meeting candidates. A cancellation may modify only one uniquely resolved app-visible SIweb meeting. Ambiguous, conflicting, nonmatching, or multi-section results must remain visibly `需要确认`; they must not become a standalone schedule-change event.
- A schedule-change signal that is `confirmed/corrected` but later loses its target meeting is unsafe. It must immediately become Calendar-ineligible, be surfaced for review/correction, and reconcile away only an app-owned bound Calendar effect. Do not delete source records or silently invent a new target.
- No confidence threshold may bypass confirmation. The UI must offer correction for provider-unavailable, `other`, pending, and unsafe previously-confirmed results. Calendar preview must identify the exact meeting and effect before the user confirms.
- Preserve distinct exam styling and all existing Apple Calendar ownership boundaries. Mailbox integration remains absent.
- Add privacy-safe migration/recovery for the existing invalid state without embedding real announcement text in code, tests, logs, commits, or handoff. Do not mutate the real database from tests.

## Regression tests and acceptance

- Add synthetic multi-section fixtures equivalent in structure to: section 311 cancellation on its Monday meeting, section 312 or makeup/response information on Friday. Assert the 311 course resolves only to the Monday SIweb meeting.
- Cover wrong provider date, multiple candidate dates, no matching meeting, target disappearing after resync, and stale `confirmed + no_target` state.
- Assert none of those unsafe states appears as a standalone app-calendar event, Apple Calendar write, or deadline notification; they remain correctable and require explicit confirmation.
- Assert an explicitly previewed and user-confirmed unique cancellation modifies the existing course meeting rather than creating a duplicate standalone event; undo restores it idempotently.
- Run focused academic-signal, reconciliation, Calendar, notification, and presentation tests, then the complete required gate from `.agent/CURRENT.md`, build/signature verification, diff check, credential/private-data scan, and mailbox-path absence assertion.
- Perform a privacy-safe signed-app real walkthrough against the existing authorized data. Report only identifiers, counts, states, timestamps, and pass/fail—not announcement bodies, credentials, cookies, tokens, or private page content. Stop at any action that would create/update/delete an EventKit event unless the user gives action-time confirmation in the main conversation.

## Handoff

Write `.agent/handoffs/stage-15s.md` with `PASS`, `PARTIAL`, or `BLOCKED`; root cause; changed files; concise command results; synthetic and aggregate real evidence; confirmation/Calendar safety evidence; release identity; and remaining manual gate. Do not accept the stage, edit central status, or start the seven-day trial.
