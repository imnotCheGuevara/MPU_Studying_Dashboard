# Stage 11 — DeepSeek provider, consent, and security gate

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-10r.md

## Prerequisite gate

Stages 08, 09, and 10R must be accepted, Stage 10 paused, and Stage 11 authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 11 only: the production DeepSeek provider plus its consent, privacy, credential, and safety gate. Do not implement Canvas-announcement classification in this stage.

Implement a production DeepSeek adapter behind the existing provider-neutral AI contract. Before coding against the service, verify the current official DeepSeek API, model, structured-output, errors/rate limits, terms, and privacy documentation; record dated links and a concise capability/retention assessment in the handoff without copying large source text. Use the documented HTTPS API origin, strict local JSON Schema validation, deterministic input/output token caps, bounded timeouts/concurrency, Retry-After-aware bounded retries, cancellation, redacted errors, input hashing, durable content+provider+model+prompt+schema caching, per-run/daily budgets, and cost/token counters that contain no content. Disable and do not expose web search, tool calls, file/image upload, remote URL fetching, or arbitrary base URLs.

Add an explicit Settings flow that is off by default and, before enablement, shows: DeepSeek as provider; reviewed policy dates/links; that selected text leaves the Mac and may be processed/stored in the PRC or outside the user's region; exact field categories that a feature may transmit; school-policy warning; current model; disable and local-result-clearing controls. Consent must be versioned, revocable, and invalidated when provider, policy disclosure, field categories, or material processing behavior changes. Store the API key only through a non-echoing local UI/Keychain path. Never ask for or print the key.

The macOS system proxy is the default route. If credential-free evidence proves it breaks DeepSeek TLS, add an off-by-default Settings option for direct HTTPS to the exact `api.deepseek.com` host only. Enabling it requires an explicit user action and localized disclosure that DeepSeek traffic will bypass the system proxy; it must not alter FlClash/VPN, global proxy settings, other hosts, or other apps. Persist only the boolean routing preference, never proxy credentials or configuration.

Allowed scope: Sources/CampusDashboard/AI, the narrow Settings/Localization surfaces required for provider configuration and consent, Keychain-backed provider configuration, additive migrations/provenance fields if necessary, focused tests, implementation docs, and .agent/handoffs/stage-11.md. Do not classify production Canvas announcements, add Outlook, alter official/inferred-date rules, call EventKit/notifications, or begin study planning.

Acceptance:
- Tests prove the provider is off until current consent and a Keychain key exist; disabling/revoking consent stops all network calls while deterministic features continue.
- Request tests prove host/method/header allowlisting, no credentials in URL/log/database, minimum payload construction contract, disabled tools/search/uploads, bounded size/concurrency/timeout/retry, cancellation, Retry-After handling, durable unchanged-input cache hits, and hard per-run/daily budget stops.
- Proxy-routing tests prove system-proxy mode is the default; direct mode is explicit and restricted to the exact allowlisted host; no global/network-system setting is changed; redirects and host changes fail closed; diagnostics reveal neither proxy configuration nor credentials.
- Response tests cover valid structured output, unknown/extra fields, wrong types, invalid dates, empty/truncated/content-filtered responses, non-JSON, 400/401/403/429/5xx, model mismatch, and prompt-injection-shaped content; every failure is side-effect free.
- Consent/disclosure tests cover English and Simplified Chinese, policy/version invalidation, payload-category preview, key rotation/removal, and independent local AI-result clearing.
- Full existing suite, clean build, signed-app verification, signing/plist checks, credential scans, and diagnostics redaction pass.
- Using a synthetic announcement only, perform one real signed-app DeepSeek smoke test. Record only status/model/token-count aggregates and confirmation that no private content or key entered output/logs. A missing key, unresolved provider retention disclosure, or failed live smoke requires PARTIAL/BLOCKED, not PASS.

Write .agent/handoffs/stage-11.md with PASS, PARTIAL, or BLOCKED; changed files; dated official references; exact checks; disclosure text categories; real-smoke aggregate evidence; and remaining risks. Do not begin Stage 12.
