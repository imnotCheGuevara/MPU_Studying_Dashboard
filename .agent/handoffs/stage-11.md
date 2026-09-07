# Stage 11 handoff

Status: PASS

## Outcome

The Stage 11 DeepSeek provider, versioned consent flow, Keychain credential boundary, request/response safety controls, budgets, durable cache, aggregate accounting, Settings disclosures, migrations, and tests are implemented and pass offline acceptance. A targeted repair now adds an off-by-default, explicit in-app direct-HTTPS preference restricted to the normalized exact host `api.deepseek.com`. The default continues to use the macOS system proxy. The repair never reads, changes, pauses, closes, reconfigures, or otherwise operates FlClash, and it does not read or modify macOS global proxy state.

The mandatory synthetic live DeepSeek smoke completed successfully at 2026-09-06 12:33:15 CST after the user explicitly enabled the in-app direct-HTTPS preference. The preserved pre-repair history below still records the two earlier signed-app system-proxy failures as `serviceUnavailable`, with zero recorded requests/tokens and no content or credential in evidence. Those historical failures were isolated to the system-proxy URLSession path (`NSURLErrorDomain -1200`, underlying `errSSLClosedNoNotify (-9816)`); they were not erased or reclassified.

The unchanged final signed bundle used the exact-host route, returned HTTP 2xx, passed strict local schema validation, stayed within configured budgets, and proved the second identical provider operation was a durable local cache hit rather than a second network request. Aggregate evidence recorded one live request, 213 input tokens, 126 output tokens, and no private-content or credential leakage. All Stage 11 mandatory acceptance items now pass; this handoff is `PASS` and awaits main-thread inspection/acceptance.

## Targeted direct-HTTPS repair

- Added schema v9 column `ai_settings.deepseek_direct_https INTEGER NOT NULL DEFAULT 0`. A real production-database boolean-only query after migration returned schema `9` and route value `0`; existing installations therefore remain on the macOS system proxy until the user acts.
- Settings now exposes `Connect directly only for DeepSeek API` / `仅 DeepSeek API 直连` with a complete localized explanation: it is off by default; only HTTPS to `api.deepseek.com` bypasses the macOS system proxy; FlClash, VPN, global network settings, other hosts, and other apps are unchanged.
- The route preference is a boolean only. It cannot set a host, URL, proxy address, proxy credentials, or rules, and it is not derived from environment variables, ordinary model output, or remote content.
- Production routing normalizes the host and requires exact `api.deepseek.com`, HTTPS, port 443/default, and no URL credentials. Subdomains, lookalike suffixes, other hosts, non-HTTPS URLs, and nonstandard ports fail closed before transport.
- System-proxy mode uses an ordinary ephemeral URLSession configuration. Explicit direct mode changes only the private DeepSeek session's `connectionProxyDictionary` to an empty dictionary. No System Configuration framework/API or global network-setting command is used.
- A URLSession task delegate refuses cross-host and HTTPS-to-HTTP redirects. The final response URL is revalidated against the same exact-host HTTPS policy.
- Diagnostics format v2 adds only `deepSeekDirectHTTPS: Bool`. No proxy host, address, port, configuration, rule, credential, authorization material, token, payload, or response body is queried or serialized.
- The aggregate-only signed smoke tool now calls the same fixed synthetic input twice: the first successful call must record the live aggregate, and the second must be a durable cache hit with no added request/tokens. Evidence includes only fixed HTTP/parsing/Stage-11-contract categories, the safe route boolean, request/token totals, budget/cache booleans, and leak booleans.

## Implemented Stage 11 scope

- Production provider fixed to `POST https://api.deepseek.com/chat/completions` and model `deepseek-v4-flash`.
- Non-streaming text-only JSON Output with non-thinking mode and `tool_choice: none`; no tools, web search, files, images, remote URL input, provider user identifier, or configurable base URL.
- Current consent requires exact provider/model, policy review dates and links, transmitted-field categories, retention warning, PRC/cross-region warning, version/signature, and affirmative school-policy confirmation.
- External AI stays disabled until current consent and a nonempty Keychain item both exist. Revocation stops calls; key removal also revokes consent. Local AI-result/cache clearing is independent of the Keychain and Calendar.
- Request input is reduced to bounded selected Canvas title, visible excerpt, minimum course name, official item type/date when present, locale, and fixed schema instructions. Stable IDs, Canvas URLs, authors/recipients, attachments, hidden HTML, credentials, remote content, and unrelated history are excluded.
- 16 KiB request cap, 64 KiB response cap, 768 output-token cap, 30-second ephemeral URLSession timeout, one local in-flight request, at most three attempts, bounded Retry-After-aware backoff, and cancellation.
- Exact-key local response validation rejects unknown/missing fields, wrong types, invalid or conflicting dates, unknown related IDs, prompt-injection-shaped output, empty/truncated/content-filtered output, model mismatch, and tool calls without applying side effects.
- Durable content/provider/model/prompt/schema cache plus hard per-run/daily request and token budgets. Usage storage contains aggregate request/input/output token counts and estimated maximum-rate micro-USD only.
- English and Simplified Chinese Settings surfaces show provider/model, secure Keychain entry state, enable/revoke controls, payload categories, policy dates/links, retention and school-policy warnings, budgets, usage aggregates, and independent AI-result clearing.
- Additive schema v8 migration for consent provenance, provider budgets, cache, and usage.

No Canvas-announcement production classification, Outlook/Microsoft Graph, official/inferred-date rule change, EventKit/notification call from AI, or study-planning work was added.

## Files attributable to Stage 11

- `Sources/CampusDashboard/AI/AIModels.swift`
- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/AI/AIPersistence.swift`
- `Sources/CampusDashboard/AI/DeepSeekLocalTool.swift` (new)
- `Sources/CampusDashboard/AI/DeepSeekProvider.swift` (new)
- `Sources/CampusDashboard/App/AppEnvironment.swift`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift`
- `Tests/CampusDashboardTests/DeepSeekProviderTests.swift` (new)
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `docs/ai-assisted-parsing.md`
- `.agent/handoffs/stage-11.md` (new)

Repair-specific edits in this continuation were limited to:

- `Sources/CampusDashboard/AI/AIModels.swift`
- `Sources/CampusDashboard/AI/AIParsingCoordinator.swift`
- `Sources/CampusDashboard/AI/AIPersistence.swift`
- `Sources/CampusDashboard/AI/DeepSeekLocalTool.swift`
- `Sources/CampusDashboard/AI/DeepSeekProvider.swift`
- `Sources/CampusDashboard/App/DashboardModel.swift`
- `Sources/CampusDashboard/App/Localization.swift`
- `Sources/CampusDashboard/Features/Settings/SettingsView.swift`
- `Sources/CampusDashboard/Persistence/DatabaseMigrator.swift`
- `Sources/CampusDashboard/Persistence/SQLiteDatabase.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsModels.swift`
- `Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift`
- `Tests/CampusDashboardTests/DeepSeekProviderTests.swift`
- `Tests/CampusDashboardTests/PersistenceTests.swift`
- `docs/ai-assisted-parsing.md`
- `.agent/handoffs/stage-11.md`

The Git repository has no commits and every project path is untracked, so `git diff` cannot reconstruct a before/after patch. Scope inspection therefore used `git status`, the complete DeepSeek reference inventory, 2026-09-06 file modification inventory, direct review of each Stage 11 implementation/integration path, and forbidden-scope scans. No central planning/specification file or other-stage handoff was edited by this completion task.

## Official references reviewed 2026-09-06

- [Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/): `POST /chat/completions`, current `deepseek-v4-flash`, `thinking.type`, JSON Output, non-streaming response shape, finish reasons, and token usage.
- [JSON Output](https://api-docs.deepseek.com/guides/json_mode/): requires `response_format: {"type":"json_object"}` plus an explicit JSON instruction; may return empty content and may truncate at the token limit. Both fail closed locally.
- [Models and pricing](https://api-docs.deepseek.com/quick_start/pricing/): current V4 Flash model, HTTPS base origin, JSON Output support, and variable peak/off-peak token pricing. The local cost value is deliberately labeled a maximum-rate estimate rather than a billing record.
- [Rate limits](https://api-docs.deepseek.com/quick_start/rate_limit/): account-level concurrency and HTTP 429 behavior. The app applies a stricter single-flight limit and bounded backoff.
- [Error codes](https://api-docs.deepseek.com/quick_start/error_codes/): 400/401/402/422/429/500/503 categories and retry guidance.
- [DeepSeek Privacy Policy](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html), last updated 2026-02-10: states that input may be collected and used for service, security, development, and improvement; provides no fixed API-input deletion period; and states direct collection, processing, and storage in the PRC, with possible storage outside the user's country.
- [DeepSeek Open Platform Terms](https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html), released 2026-04-22 and effective 2026-04-29: requires developers to disclose downstream processing and obtain consent or another valid basis, and requires API keys to be kept secure.
- [DeepSeek service status](https://status.deepseek.com/): reported the V4 Flash API operational while the local TLS failure was reproduced.

Capability/retention assessment: the current API supports the fixed text-only JSON Output request used here, but JSON validity is not treated as schema validity and provider output remains untrusted. The reviewed policy does not support a no-retention claim. Selected text must be treated as externally retained/processed in the PRC or outside the user's region, and must not be sent when school policy forbids that processing.

## Disclosure categories checked

- DeepSeek legal entity and current model.
- Selected text leaves the Mac.
- PRC and cross-region processing/storage warning.
- Exact possible fields: selected Canvas title; bounded visible excerpt; minimum course name; official type and official due date when present; interface locale; fixed schema instructions.
- Explicit exclusions: Canvas URL, account/student identifiers, author email, recipients, attachments, cookies/tokens, hidden HTML, remote content, and unrelated history.
- Privacy-policy review date/link and Open Platform terms release/effective dates/link.
- No fixed API-input deletion period; possible service, legal, security, and improvement retention/use.
- School-policy prohibition warning and affirmative confirmation.
- Current consent enablement, revocation/disable, secure key removal, budgets/usage, and independent local AI-result clearing.

## Automated, build, signing, localization, and scan evidence

Verbose successful logs are retained under `/tmp/campus-stage11.mG00uy`.

```sh
./scripts/test.sh --filter DeepSeekProviderTests
# PASS: 13 tests / 1 suite, 0 failures, 0.107s.

./scripts/test.sh
# PASS: 177 tests / 16 suites, 0 failures, 0.505s.

swift package clean
swift build --jobs 1
# PASS: clean debug build, 41.69s.

./scripts/build-app.sh
# PASS: release build, 48.04s; signed dist/Campus Dashboard.app produced.

./scripts/verify-app.sh
# PASS: Launch Services launch and packaged Keychain create/read/delete smoke.

codesign --verify --deep --strict "dist/Campus Dashboard.app"
# PASS.

plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
# PASS: both property lists valid.

codesign -d --entitlements :- "dist/Campus Dashboard.app"
# PASS: app sandbox, outbound network client, and Calendar entitlements present.

ruby -e '<inventory model.text/Localizer.text literals and require Localization.swift entries>'
# PASS: 166 literal localization keys, 0 missing.

./scripts/test.sh --filter localizedDisclosure
# PASS: 1 test / 1 suite; every required disclosure string has distinct Simplified Chinese presentation.

! rg -n '<credential/private-key patterns>' --hidden \
  --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
# PASS: no credential or private-key pattern found.

! rg -n 'import (EventKit|UserNotifications)|Mail\.|Microsoft Graph|Outlook|study planning|Phase 2' \
  Sources/CampusDashboard/AI Tests/CampusDashboardTests/DeepSeekProviderTests.swift
# PASS: no forbidden cross-stage/framework reference.

rg -n 'authorization|cookie|response_json|input|output|payload|source_url|title|summary|content' \
  Sources/CampusDashboard/Privacy/PrivacyDiagnosticsService.swift
# PASS after inspection: matches are only allowlisted authorization-state categories/comments/encoder configuration; diagnostics do not query or serialize AI request/response bodies, cache JSON, content, title, source URL, or identifiers.

! rg -n '[[:blank:]]+$' <Stage-11 attributable paths>
git diff --check
# PASS: no trailing whitespace; tracked diff check clean (repository remains all-untracked, as noted above).
```

Focused coverage includes off-by-default/current-consent/Keychain gating; revoked-consent zero-call behavior; fixed host/method/headers; minimum payload and forbidden-capability exclusions; request/response limits; single-flight concurrency; timeouts/offline/cancellation; Retry-After and bounded retry; durable cache; per-run/daily budgets; aggregate usage; valid output; extra/unknown/wrongly typed fields; invalid dates; empty/non-JSON/truncated/content-filtered output; 400/401/402/403/429/5xx; model mismatch; prompt-injection-shaped content; key rotation/removal; consent invalidation; independent local-result clearing; and bilingual disclosure presentation.

### Targeted repair verification (2026-09-06 Asia/Macau)

Successful verbose logs are retained under `/tmp/campus-stage11-direct.7V9UDJ`.

```sh
./scripts/test.sh --filter DeepSeekProviderTests
# PASS: 16 tests / 1 suite. Added default-system/explicit-direct routing,
# exact-host/scheme/port/credential/redirect refusal, safe diagnostics, and bilingual copy.

./scripts/test.sh --filter PersistenceTests
# PASS: 13 tests / 1 suite, including v8 -> v9 default-false migration.

./scripts/test.sh --filter PrivacyDiagnosticsTests
# PASS: 5 tests / 1 suite; existing adversarial redaction and responsiveness retained.

./scripts/test.sh
# PASS: 181 tests / 16 suites, 0 failures, 0.617s test execution.

swift package clean
swift build --jobs 1
# PASS: clean Debug build, 72.32s.

./scripts/build-app.sh
# PASS: Release build, 77.57s; signed dist/Campus Dashboard.app produced.

./scripts/verify-app.sh
codesign --verify --deep --strict "dist/Campus Dashboard.app"
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
codesign -d --entitlements :- "dist/Campus Dashboard.app"
# PASS: Launch Services and packaged Keychain smoke, strict signature, both plists,
# app sandbox, outbound network-client, and Calendar entitlements.

ruby -e '<inventory model.text/Localizer.text literals and require Localization.swift entries>'
# PASS: 168 literal localization keys, 0 missing.

! rg -n '<credential/private-key patterns>' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
# PASS: no credential/private-key pattern found.

! rg -n 'SCDynamicStore|SCPreferences|SystemConfiguration|networksetup|CFNetworkCopySystemProxySettings|CFNetworkExecuteProxyAutoConfiguration|setenv\\(|ProcessInfo.*environment' <Stage-11 routing paths>
otool -L "dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" | rg 'SystemConfiguration'
# PASS: no global proxy-setting/read API, environment-based host override, command,
# or linked SystemConfiguration framework.

! rg -n 'proxyAddress|proxyHost|proxyPort|proxyPassword|connectionProxyDictionary|authorization_header|cookie_value|proxy_credentials' Sources/CampusDashboard/Privacy
# PASS: diagnostics expose only the fixed boolean route state.

! rg -n 'import (EventKit|UserNotifications)|Mail\\.|Microsoft Graph|Outlook|study planning|Phase 2' Sources/CampusDashboard/AI Tests/CampusDashboardTests/DeepSeekProviderTests.swift
# PASS: no Stage 12/Outlook/future-stage or forbidden side-effect scope.

! rg -n '[[:blank:]]+$' <repair-specific paths>
git diff --check
# PASS: whitespace checks clean; repository remains all-untracked as previously recorded.

sqlite3 <production-app-database> 'SELECT (SELECT user_version FROM pragma_user_version), deepseek_direct_https FROM ai_settings WHERE singleton_key=1;'
# PASS, boolean-only output: 9|0. No content, identifier, key, token, proxy detail,
# or other configuration was read.
```

Read-only signed-binary inspection confirmed the final executable contains the English control
and explanation strings plus the `deepSeekDirectHTTPS` diagnostic key. The pre-build resident
process was identified and closed; two verification-only Campus Dashboard instances were also
closed afterward. A fresh production instance reached the existing Keychain authorization
boundary and AX inspection timed out, so no Keychain prompt was accepted and no route toggle was
clicked. Source-backed SwiftUI inspection plus the focused localization/routing tests provide the
remaining UI evidence without changing network state. FlClash was never opened, clicked, read,
paused, closed, switched, or reconfigured.

## Signed Settings verification

On 2026-09-06 Asia/Macau, the final signed production app was inspected through the macOS accessibility tree without interacting with the secure key field or exposing its value.

- PASS, Simplified Chinese: Settings reported DeepSeek enabled with current consent, the current V4 Flash model, API key stored only in Keychain, aggregate usage only, revoke/disable, key removal, budgets, and independent local AI-result clearing. All app-owned labels were localized.
- PASS, English: runtime language switching updated the same Settings/provider/key/usage/revoke/clear surfaces without restart.
- PASS: the secure field exposed no value in the accessibility tree. The app's language was restored to Simplified Chinese after inspection.
- PASS: the focused disclosure test independently verifies both languages for the modal's provider/transmission/retention/school-policy/consent wording. Source inspection confirms the modal also renders both dated official links and the exact transmitted-field list.

No Settings action removed a key, revoked consent, cleared results, or changed Calendar/notification/source state.

## Live signed-app smoke evidence

Only the fixed synthetic announcement embedded in `DeepSeekLocalTool` was used. No school record, private content, source URL, account/student identifier, credential, or response body entered commands, output, logs, screenshots, or this handoff.

| Local time (Asia/Macau) | Signed-app result | Aggregate evidence |
| --- | --- | --- |
| 2026-09-06 00:41:49 CST | Safe pre-consent attempt preserved | `blocked`, category `consent_required`, model `deepseek-v4-flash`, requests 0, input tokens 0, output tokens 0, private-content flag false, credential flag false. |
| 2026-09-06 11:19:27 CST | Current consent/key recognized; live request failed safely | `blocked`, category `serviceUnavailable`, model `deepseek-v4-flash`, requests 0, input tokens 0, output tokens 0, private-content flag false, credential flag false. |
| 2026-09-06 11:33:01 CST | Final rebuilt signed-app retry; same safe failure | `blocked`, category `serviceUnavailable`, model `deepseek-v4-flash`, requests 0, input tokens 0, output tokens 0, private-content flag false, credential flag false. |
| 2026-09-06 12:33:15 CST | PASS on unchanged signed bundle after explicit user route enablement | `status=pass`; fixed model `deepseek-v4-flash`; `directHTTPS=true`; HTTP category `success_2xx`; parsing category `strict_schema_pass`; Stage 11 classification category `stage11_provider_contract_only`; one live request; 213 input tokens; 126 output tokens; budget and durable-cache checks true; private-content and credential flags false. |

The production database gate query after user setup showed enabled external-provider state, current consent version, school-policy confirmation, current model, and bounded budgets. It did not read or output any Keychain value. The transition from `consent_required` to transport-level `serviceUnavailable`, plus the signed Settings state, proves the current signed app recognizes the Keychain/consent gate.

Credential-free diagnosis:

```sh
curl --silent --show-error --connect-timeout 10 --max-time 20 \
  --output /dev/null --write-out 'https_code=%{http_code}\n' https://api.deepseek.com
# PASS reachability: HTTP 401, expected without a credential.

swift -e '<ephemeral URLSession GET to https://api.deepseek.com>'
# BLOCKED on current system proxy path: NSURLErrorDomain -1200.

nscurl --ats-diagnostics --verbose https://api.deepseek.com
# BLOCKED across ATS permutations: underlying TLS error -9816 (server closed without TLS close notification).

swift -e '<same credential-free ephemeral URLSession GET with proxy dictionary empty>'
# PASS direct path: HTTP 401, expected without a credential.
```

No certificate-validation exception, insecure HTTP allowance, arbitrary host, credential export, or external command using the API key was attempted. The successful call used the API key only through the existing signed-app Keychain boundary.

## Final live acceptance and immutable-bundle evidence

The earlier recommendation to reconfigure or pause a proxy/VPN is superseded and was not followed. FlClash was not opened, clicked, read, paused, closed, switched, or reconfigured, and macOS global proxy state was neither read nor modified. The user explicitly enabled **Connect directly only for DeepSeek API** / **仅 DeepSeek API 直连** in the final signed app.

Before the only post-enable smoke, read-only preflight showed schema v9, route boolean `1`, budgets 10 per-run/50 daily requests and 20,000 per-run/100,000 daily tokens, zero provider-cache rows, and zero usage aggregates. The executable was recorded as:

```text
SHA-256 969b6fed865e6bb6b69ac03e78b0bba6644c603afbab972e8d2fd33510100092
CDHash  d66bd0b3ed00a69f7e1a0b28c381e61b617dbf44
size    4,993,312 bytes
mtime   2026-09-06 12:02:07 CST
bundle  com.campusdashboard.desktop, ad-hoc signed arm64
```

Exactly one smoke command was run against that bundle:

```sh
open -n -W "dist/Campus Dashboard.app" --args --deepseek-smoke-test \
  "/Users/yang/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/deepseek-stage11-final-retry.json"
```

The command exited 0 and its exact allowlisted aggregate fields reported: `status=pass`, `directHTTPS=true`, `httpCategory=success_2xx`, `parsingCategory=strict_schema_pass`, `classificationCategory=stage11_provider_contract_only`, model `deepseek-v4-flash`, request count 1, input tokens 213, output tokens 126, `withinConfiguredBudget=true`, `cacheHitVerified=true`, `containedPrivateContent=false`, and `containedCredential=false`. The network URLSession cache remains disabled; the required durable provider cache contained exactly one validated result, and the second identical internal operation caused no additional request/token usage.

Post-smoke SHA-256 and CDHash were byte-for-byte identical to preflight. Strict signature verification, both plist lints, the whole-tree credential scan, diagnostic/evidence allowlist scan, response-body/secret-field absence check, global-proxy API scan, and absence of a linked SystemConfiguration framework all passed. Persisted aggregate usage was exactly `1 | 213 | 126` and the route boolean remained `1`.

The strict Stage 11 schema requires bounded confidence, a nonempty rationale, conflict/uncertainty fields, and local-only confirmation semantics; `strict_schema_pass` proves those structural requirements for the live response without exposing its content. The provider transport has no EventKit or notification authority, and the 181-test suite retains the confirmation gate. The four production announcement taxonomy classes (`course_schedule_change`, `assignment_deadline`, `exam_time`, `other`) belong to locked Stage 12 and were deliberately neither implemented nor claimed here; `stage11_provider_contract_only` makes that boundary explicit.

## Conclusion

All Stage 11 implementation, offline safety, routing regression, complete-suite, Debug/Release build, signing, plist/entitlement, scan, migration, diagnostic, bilingual Settings, and mandatory real signed-app smoke requirements pass. The final bundle defaults to the macOS system proxy and uses the exact-host direct route only after the user's explicit choice, without touching FlClash or global network state. This handoff is `PASS` and awaits main-thread inspection and acceptance. No Stage 12 work was started or authorized.
