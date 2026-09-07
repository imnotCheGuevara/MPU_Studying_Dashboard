# Stage 14 — Outlook read-only mail sync and local mailbox UI

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-13.md

## Prerequisite gate

Stage 14 is deferred outside the active release path. It requires accepted Stage 13 and a future explicit main-thread authorization; otherwise stop without implementation.

## Stage contract

You own Stage 14 only: read-only Microsoft Graph mail synchronization and the local school-mailbox experience.

Implement Graph reads for user-selected folders, initially Inbox, with a bounded configurable recent window and minimum `$select` fields. Use the accepted stable message-ID strategy and per-folder delta query/pagination. Store continuation/delta state as sensitive opaque connector state, never diagnostics. Integrate Outlook as an independently failing source with transactional normalization, durable local state, idempotency, conservative deletion evidence, retries honoring `Retry-After`, refresh-token recovery, and manual/hourly sync behavior.

Default to metadata available under `Mail.ReadBasic`. If the user explicitly enables body display and the feature requires it, present a separate permission explanation and upgrade only to delegated `Mail.Read`; remain useful when denied. Sanitize HTML locally, do not execute scripts, load remote images/tracking pixels, auto-open links, or download attachments. Never send, reply, forward, move, delete, archive, categorize, flag, or remotely mark read. Local read/hidden/important state never writes back. Do not send Outlook content to DeepSeek in this stage.

Add a localized School Mail page with source health, last successful sync, folder/window controls, sender display, subject, received time, safe preview, original Outlook link, local read/hidden controls, loading/empty/error/permission/admin-gate states, and clear source-original versus local state presentation. Preserve source language.

Allowed scope: Outlook connector and DTOs, unified MailMessage persistence/read models/migrations, sync orchestration integration, School Mail UI/localization, settings/privacy clearing/diagnostics redaction, focused tests, and .agent/handoffs/stage-14.md. Do not add mail AI classification, Outlook write operations, Outlook Calendar/contacts, attachment download, or study planning.

Acceptance:
- Fake Graph tests cover first page, pagination, delta next/delta links, creates/updates/moves/deletes, incomplete pagination, invalid delta resync, 401 refresh, 403 consent/admin gate, 404 folder, 429 Retry-After, 5xx, timeout, cancellation, malformed payload, timezone and HTML/tracker sanitization.
- Repeated sync/restart is idempotent; one missing item or broken page never deletes; Outlook failure does not block Canvas/SIweb; first baseline causes no notification storm.
- Network tests prove GET-only allowlisted Graph routes, minimum fields, bounded concurrency/window, no redirect/host escape, and no remote-content fetching.
- Privacy tests prove tokens/delta state/addresses/subjects/bodies/message IDs never enter logs, diagnostics, fixtures, screenshots, or handoff; category clearing is separate from credentials and calendar.
- UI/accessibility/localization checks pass at supported window sizes in English and Simplified Chinese; source text remains original.
- Full suite, clean/release build, signed-app verification, signing/plist/security scans, and real school-mailbox initial plus incremental read-only smoke pass with aggregate-only evidence.

Write .agent/handoffs/stage-14.md with PASS, PARTIAL, or BLOCKED and exact evidence. Do not begin Stage 15.
