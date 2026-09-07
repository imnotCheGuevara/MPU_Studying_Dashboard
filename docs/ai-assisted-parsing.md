# Controlled AI-assisted parsing

## DeepSeek production provider boundary (reviewed 2026-09-06)

The production external provider is fixed to `POST https://api.deepseek.com/chat/completions`
with `deepseek-v4-flash`, non-streaming JSON Output, non-thinking mode, and
`tool_choice: none`. There is no configurable base URL, and the request contains no tools,
web-search capability, files, images, remote URLs, or provider user identifier. The response is
accepted only after envelope checks and exact-key local schema validation.

External processing is off by default. Enabling requires an API key stored only in macOS
Keychain and a versioned consent signature covering provider/model, reviewed policy dates and
links, transmitted fields, PRC/cross-region processing, retention uncertainty, and school-policy
confirmation. Revocation disables requests; key removal also revokes consent. Local AI results
and cache can be cleared separately from credentials and Calendar data.

Only a bounded selected title, visible text excerpt, minimum course name, source-provided type
and due date when present, locale, and fixed schema instruction are sent. Stable object/account
IDs, Canvas/source URLs, author or recipient data, attachments, hidden HTML, credentials, and
unrelated history are excluded. Payload and response bodies never enter diagnostics.

The adapter uses a 30-second ephemeral session, one local in-flight request, at most three
attempts, bounded `Retry-After`-aware delay, cancellation, a 16 KiB request cap, 768-token output
cap, and a 64 KiB response cap. A durable SHA-256 cache includes content plus
provider/model/prompt/schema identity. Per-run and daily request/token budgets stop before a paid
call. Stored usage contains only aggregate token/request counts and an estimated maximum-rate
micro-USD counter; prices can change and this is not a billing record.

The default ephemeral session follows the macOS system proxy. Settings also exposes a separate,
off-by-default `DeepSeek API only` direct-HTTPS preference. When the user explicitly enables it,
only HTTPS requests whose normalized host is exactly `api.deepseek.com` receive an ephemeral
session configuration with an empty per-session proxy dictionary. The request allowlist rejects
other hosts, subdomains, non-HTTPS URLs, nonstandard ports, and URL credentials; redirects to a
different host or a non-HTTPS URL are refused. The preference cannot change the fixed API origin.
No System Configuration API is used, and the app does not inspect or modify FlClash, VPN, macOS
global proxy state, other applications, or traffic for another host. Diagnostics expose only the
boolean route preference and never a proxy address, port, rule, credential, or configuration.

Official references reviewed on 2026-09-06:

- [Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/)
- [JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- [Models and pricing](https://api-docs.deepseek.com/quick_start/pricing/)
- [Rate limits](https://api-docs.deepseek.com/quick_start/rate_limit/)
- [Error codes](https://api-docs.deepseek.com/quick_start/error_codes/)
- [DeepSeek Privacy Policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html)
- [DeepSeek Open Platform Terms](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html)

The reviewed privacy policy says inputs may be used to provide, secure, develop, and improve
services; it gives no fixed API-input deletion period and states that personal data is directly
collected, processed, and stored in the PRC. The Open Platform terms say downstream developers
control their end-user processing and must provide the relevant disclosure and consent basis.
The app therefore makes no no-retention claim and warns users not to enable the provider when
school policy forbids external processing.

Stage 08 introduced the provider-neutral `AIParsingProvider` boundary on top of the committed Canvas/raw-record and unified-model stores. Stage 11 adds the gated DeepSeek implementation while retaining the deterministic local fixture for tests. Production external AI remains disabled until the current consent and Keychain gates are satisfied.

## Processing boundary

Deterministic normalization runs and commits first. If AI is enabled, only committed Canvas learning-task and announcement records are considered. Inputs contain bounded title/type/course/date fields, at most 1,200 characters of relevant text, and at most eight typed known-object summaries from committed tasks and announcements in the same course. The current object and other courses are excluded. Each known-object summary contains only its stable local ID, object kind, short title/type, and one relevant date. URLs and credential-like text are redacted from both the target and known-object context before hashing or provider dispatch. SIweb, credentials, cookies, login pages, attachments, complete source bodies, and unrelated history are excluded.

Provider output must be one JSON object with the exact v2 schema and must not exceed 32 KiB. Unknown, missing, wrongly typed, oversized, non-finite, or out-of-range values are rejected. `normalizedTitle` is limited to 240 characters and `suggestedType` to 80 characters. Related IDs may reference only the known objects supplied in that request. An echoed official date must exactly match the source date. Provider errors and invalid output create a safe failure record and cannot roll back or change synchronized source data.

## Authority and confirmation

- Official dates are read-only and always take precedence.
- Every provider-suggested date has durable `inferred` provenance, regardless of confidence.
- Deterministic and existing user values win over AI suggestions.
- Related/duplicate IDs remain suggestions; source records are never deleted or merged.
- Pending results cannot create Calendar outbox work or deadline notifications.
- Confirming or correcting an inferred date records an audit transition and a durable Calendar desired-state reconcile intent; the existing Calendar boundary independently re-checks current official/confirmed dates when the intent is consumed.
- Rejection applies nothing. Undo restores the exact pre-confirmation task fields from `ai_applied_values` and records another audit transition.
- Undo records another deterministic, replay-safe Calendar reconcile intent. If the task has no remaining eligible date, an existing app-bound event is removed; if an official date remains, the same bound event is preserved or restored to that official date. A stale pre-undo upsert is evaluated against current committed state and cannot create an obsolete event or retry forever merely because the inferred date disappeared.
- The application orchestration layer asks the existing notification service to perform desired-state reconciliation after undo. The AI module never imports or calls EventKit or UserNotifications.
- Dashboard confirmation, correction, and undo actions are async through notification convergence: after the local AI decision commits, the caller does not return until the notification service has completed desired-state reconciliation. SwiftUI starts these async model operations from its synchronous button closures. If reconciliation fails, the committed AI decision is retained and the queue reports that the decision was saved while deadline notifications still need a later refresh; notification failure never rolls the decision back.

The confirmation queue displays source target, AI values, confidence, rationale, conflicts, provider/model/prompt/schema provenance, and final adopted values. External providers cannot be enabled unless provider disclosure, transmitted-field categories, retention policy, and explicit consent have all been stored.

## Synthetic evaluation

The test evaluation set reports classification accuracy, duplicate-suggestion precision, date-extraction accuracy, uncertainty recall, and unauthorized Calendar/notification writes. Stage 08 requires both unauthorized-write counts to remain zero before confirmation. This is a safety regression set, not a claim about a remote model or real student data.
