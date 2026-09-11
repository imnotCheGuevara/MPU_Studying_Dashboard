# Campus Dashboard global constraints

These constraints apply to every stage and take precedence over implementation convenience. They may only be changed by the main project conversation with the user's approval.

## 1. Product boundary

- The product has personal, local-only macOS and Windows desktop distributions. Both use one canonical domain and read-only source model wherever practical.
- Phase 1 aggregates learning data from Canvas and the school website/SIweb, shows it locally, schedules local notifications, and synchronizes approved events to a dedicated Apple calendar.
- Canvas uses its API. The school website/SIweb uses an authorized, read-only crawler.
- Phase 1 does not submit assignments or quizzes, change attendance or school records, mark remote content read/completed, or write to any school system.
- Phase 1 does not add multi-user accounts, a cloud backend, a public release, or a native iPhone app.
- The approved extension adds an explicitly enabled DeepSeek API provider for Canvas-announcement classification. It does not add AI study planning, autonomous actions, or mailbox integration.
- The Windows distribution keeps Today and Schedule inside the app and deliberately omits iCloud, Apple Calendar, Outlook/Graph, CalDAV, and every other external-calendar integration.

## 2. Source access

- Canvas access is read-only and uses the school-supported API authorization method.
- The SIweb crawler may read only pages the user can normally access and that are in the agreed scope.
- Never bypass SSO, MFA, CAPTCHA, robots/access controls, rate limits, or institutional restrictions.
- Never automate state-changing forms or requests on the school website.
- Treat HTML/DOM changes as a connector failure. Do not silently emit guessed course data.
- Each connector must implement bounded concurrency, rate limiting, timeout handling, retry rules, and redacted diagnostics.
- A failure in one source must not block the other source.

## 3. Data architecture

- Store a minimal raw source record before deterministic normalization.
- UI, calendar, notifications, and AI consume the unified domain model, not third-party response objects.
- Source identity is the composite `(sourceAccountID, sourceObjectID)`. Titles are never unique identifiers.
- Official dates, user dates, and AI-suggested dates are separate fields.
- Source state and local read/completion state are separate and local state is never written back.
- Synchronization and side effects must be idempotent.
- Calendar and notification writes occur through a durable outbox after the database transaction commits.
- A single missing item is never deletion evidence. Follow the deletion rules in `docs/project-spec.md`.

## 4. Calendar ownership

This section applies only to the macOS distribution. The Windows target has no external-calendar adapter or settings surface.

- The app manages only a user-selected or app-created dedicated calendar, normally named `Campus Dashboard`.
- Calendar name alone is not identity. Persist and verify the EventKit calendar/source identity and per-event binding.
- Never modify or delete an event without a valid app-owned binding.
- Never modify personal, family, shared, subscribed, or unrelated calendars.
- AI never calls EventKit.
- Inferred dates require explicit user confirmation before calendar creation, update, deletion, or deadline notification.

## 5. AI boundary

- Deterministic Canvas fields and rules always take precedence over AI output.
- AI receives only the minimum necessary content already lawfully synchronized to the local database.
- Never send passwords, tokens, cookies, complete login pages, or unrelated personal data to AI.
- AI may suggest classification, normalized titles, related items, action summaries, priority, or completion dates.
- AI must not overwrite an official due date, merge/delete source records, browse/login, write to a source, call the calendar, or call notifications.
- Every inferred date is marked `inferred` and requires confirmation regardless of confidence.
- External AI is off by default until provider, transmitted fields, retention information, and user consent are implemented.
- AI failure must not block deterministic sync.
- DeepSeek is an external processor, not a trusted source of official facts. Its API key lives only in the platform-native credential store, requests use only the documented HTTPS API origin, and production requests must disable provider web search, tools, file upload, image input, and remote URL retrieval.
- DeepSeek uses the operating system proxy by default. If that proxy demonstrably breaks TLS, the app may offer an off-by-default, explicit user-controlled direct-HTTPS mode restricted to the exact allowlisted DeepSeek API host. The UI must explain that only DeepSeek traffic bypasses the system proxy. The app must never modify, stop, reconfigure, or inspect credentials/configuration of the user's proxy/VPN application.
- Before each external-AI feature is enabled, the UI must identify DeepSeek, explain that selected Canvas text leaves the Mac and may be processed/stored outside the user's region, link or date the reviewed provider terms/privacy notice, list the transmitted field categories, and obtain revocable opt-in consent. The user must be able to preview the payload categories and clear local AI results independently.
- Canvas announcement analysis may send only the selected announcement's minimal title/body excerpt, source-provided course context reduced to the minimum needed, locale, and schema instructions. Do not send student identifiers, Canvas URLs, author email addresses, recipient lists, attachment contents, hidden HTML, access metadata, or unrelated historical records.
- DeepSeek output is untrusted input. Validate it against a strict local schema and fixed taxonomy; reject extra/unknown fields, invalid dates, prompt-injection attempts, truncated/empty output, and unsupported model responses without side effects.

## 6. Secrets, privacy, and logs

- Store credentials, access tokens, refresh tokens, and permitted session secrets only in the platform-native credential facility: macOS Keychain on macOS, and Windows Credential Manager or DPAPI-backed storage on Windows.
- Never store secrets in source, Git, SQLite, sample data, logs, screenshots, fixtures, ordinary configuration, command history, or task handoffs.
- Never ask the user to paste a credential into a task message. Use an interactive app flow, Keychain, or a non-echoing local mechanism.
- Redact authorization headers, cookies, URL secrets, identifiers, response bodies, and personal content from diagnostics.
- Fixtures and sample data must be synthetic or irreversibly sanitized.
- The DeepSeek API key is native-credential-store-only. Announcement bodies, AI payloads, provider responses, and remote request identifiers must not appear in logs, diagnostics, screenshots, fixtures, or handoffs.
- Local data and logs must support explicit category-based clearing. Clearing local state must not implicitly delete calendar events.

## 7. Platform behavior

- The recommended stack is Swift, SwiftUI, URLSession, SQLite or SwiftData, Keychain, EventKit, UserNotifications, Service Management, and OSLog.
- The app must remain useful when Calendar, Notification, AI, or background permissions are denied.
- “Hourly sync” is a target interval while the user is logged in and the Mac can run. Sleep/offline recovery triggers a compensating sync.
- Background behavior must be visible, user-controllable, and must not imply guaranteed execution while the Mac is asleep or off.
- The production UI supports complete English and Simplified Chinese system localization. Dates, weekdays, controls, status, errors, sync explanations, dialogs, accessibility labels, and empty states must follow the selected app language and locale.
- Source-owned text such as course names, announcement titles/bodies, teacher-authored descriptions, and locations remains in its original source language unless a future explicitly authorized translation feature is added. The UI must not present invented translations as source content.
- Calendar-style UI may follow familiar macOS interaction and spatial conventions, but must not copy Apple trademarks, proprietary artwork, private assets, or pixel-identical product presentation.
- On Windows, prefer a native WinUI presentation while reusing compatible Swift domain and service code. The Windows UI must follow Windows keyboard, scaling, accessibility, and window conventions.
- The Windows product must remain useful without notification or background permission and must not show unavailable iCloud or external-calendar controls.
- Windows background behavior is best-effort while the user is logged in and the PC can run; sleep/offline recovery triggers a compensating sync and no always-running guarantee is implied.

## 8. Engineering quality

- Keep connectors, domain logic, persistence, sync orchestration, calendar, notifications, AI, and UI behind testable boundaries.
- Use migrations for persisted schema changes.
- Prefer deterministic fixture tests for connector parsing and failure modes.
- Add tests for every fixed regression and every rule with deletion or external-side-effect risk.
- Do not use live school or external-calendar services in ordinary automated tests.
- Do not claim a check passed unless it was run. Record exact commands and concise results in the stage handoff.
- Keep UI responsive; network, parsing, database, AI, and EventKit operations must not block the main thread.

## 9. Change control

- Stage conversations must not edit this file, the roadmap, `.agent/STATUS.md`, the stage prompts, the project specification, or another stage's handoff.
- If the requested stage conflicts with these constraints, stop and report the conflict to the main conversation.
- If credentials, URLs, a real device, system permission, or user action is mandatory, complete all safe offline work and mark the exact remaining acceptance item `BLOCKED` or `PARTIAL`.
