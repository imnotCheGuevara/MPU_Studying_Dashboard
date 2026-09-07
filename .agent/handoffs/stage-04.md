# Stage 04 handoff

Status: PASS

## Scope delivered

- Added an authorized, deny-by-default `SIwebConnector` behind the Stage 02 `SIwebService` boundary. It accepts only explicitly configured same-origin HTTPS targets, sends body-free `GET` requests, and rejects unknown routes before transport.
- Added an ephemeral URLSession transport with cookie persistence/cache disabled, a cancellation-safe concurrency gate, and a reservation-based request pacer. Its production task delegate refuses every automatic HTTP redirect so the original 3xx reaches connector classification without a second request or Cookie forwarding. Production defaults are one in-flight request and at least one second between starts; retry is limited to 429, 5xx, and temporary transport failures.
- Added category-only diagnostics for configuration, unsafe route, forbidden/not found, rate limiting, server/transport failures, session expiry, login redirects, partial response, malformed response, and structural change.
- Added the generic synthetic fail-closed parser contract `siweb-schedule-v1.0.0`, including cancellation mapping, stable identity, exact-offset timestamps, optional fields, content hash, explicit empty state, completeness gates, and bounded allowlisted pagination.
- Added the target-specific fail-closed MPU parser `mpu-time-stud-v1.0.0` for Lecture Information → Class Time. MPU publishes the interactive entry at `https://wapps2.mpu.edu.mo/siweb_cas/`, while the only crawler origin/path is the operational IPM target `https://wapps2.ipm.edu.mo/siweb_cas/time_stud.asp`. It validates the exact 14-column table, supports full and continuation rows, expands `yyyy/MM/dd-yyyy/MM/dd` periods and weekday dots in `Asia/Macau`, and derives deterministic versioned meeting IDs.
- Added a signed-app `--siweb-authenticate` flow using a non-persistent WKWebView. The user signs in directly on MPU pages. The app does not read the login form; after successful navigation it retains only unexpired secure cookies valid for the exact SIweb target and stores the serialized session only in macOS Keychain.
- Added `--siweb-smoke-test`, which prints only meeting/cancellation aggregates or a redacted error category.
- Added synthetic MPU and generic SIweb fixtures plus 22 Stage 04 tests covering parsing, failure modes, authorization, cookie filtering, read-only requests, redirect refusal, endpoint identity, rate/concurrency limits, retry, redaction, pagination, and idempotence.
- Extended `SIwebMeetingPayload` only as narrowly required by this connector boundary. No Stage 05+ persistence/orchestration, EventKit, notification, background scheduling, or AI implementation was added.

## Changed files

- `Package.swift`
- `README.md`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/Services/ServiceContracts.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebConfiguration.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebConcurrencyGate.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebConnector.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebHTMLParser.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebLocalTool.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebSnapshotLoader.swift`
- `Sources/CampusDashboard/Connectors/SIweb/SIwebWebAuthenticationTool.swift`
- `Tests/CampusDashboardTests/SIwebConnectorTests.swift`
- `Tests/CampusDashboardTests/Fixtures/SIweb/normal.html`
- `Tests/CampusDashboardTests/Fixtures/SIweb/empty.html`
- `Tests/CampusDashboardTests/Fixtures/SIweb/login.html`
- `Tests/CampusDashboardTests/Fixtures/SIweb/partial.html`
- `Tests/CampusDashboardTests/Fixtures/SIweb/changed-dom.html`
- `Tests/CampusDashboardTests/Fixtures/SIweb/mpu-class-time.html`
- `docs/siweb-connector.md`
- `.agent/handoffs/stage-04.md`

No main-thread-owned constraint, roadmap, status, stage prompt, project specification, or earlier-stage handoff was edited.

## Acceptance evidence

| Acceptance item | Evidence/result |
| --- | --- |
| Clean build | PASS — `swift package clean && swift build --jobs 1` completed successfully. |
| Full automated suite | PASS — `./scripts/test.sh` ran 58 tests in 6 suites; all passed. The SIweb suite contains 22 tests. |
| Generic parsing and edge cases | PASS — synthetic fixtures cover normal/empty/multiple meetings, optional fields, cancellation, explicit UTC offsets, timezone edges, deterministic identities, hash/version, malformed content, partial pages, changed DOM, login/session expiry, and conflicting duplicates. |
| MPU real-contract parsing | PASS — sanitized synthetic regression coverage verifies exact headers, complete empty pages, full rows, continuation rows, date-range recurrence expansion, weekday dots, and fail-closed behavior for malformed periods/missing weekdays/changed structure. The production decoder also has a Big5 fallback for the legacy page. |
| Read-only allowlist | PASS — tests and source scan verify body-free `GET` only, exact allowlisted target, pre-transport cross-origin rejection, and no SIweb POST/PUT/PATCH/DELETE/upload implementation. |
| Transport-level redirect refusal | PASS — a loopback TCP HTTP server exercised the production `URLSessionSIwebTransport`. It returned a 302 from `/start` with a same-origin `/target` location. The transport returned the original 302; the server observed only `/start`, never `/target`, and therefore no redirect-target Cookie. The connector regression independently classifies the raw 302 as `loginRedirect`. |
| Canonical endpoint identity | PASS — production constants and tests distinguish the published MPU entry `wapps2.mpu.edu.mo` from the only operational crawler base/target on `wapps2.ipm.edu.mo`; cookie capture accepts only the operational target domain. |
| Concurrency/rate/retry | PASS — tests bound concurrent starts, enforce minimum spacing, cap retry, honor numeric `Retry-After`, and do not retry authentication/route/parser failures. |
| Authorization and secret boundary | PASS — the user completed MPU SSO personally inside the non-persistent app web view. Only target-domain secure unexpired cookies were selected and saved in Keychain. Cookie boundary and header-injection tests passed. No credential/session value was supplied to crawler arguments, repository files, fixtures, diagnostics, or this handoff. |
| Redacted diagnostics/privacy | PASS — tests verify category-only failures. The real check emitted aggregate counts only. Repository credential scan passed. |
| Signed app | PASS — `./scripts/build-app.sh` succeeded; `./scripts/verify-app.sh` reported `PASS com.campusdashboard.desktop`; strict codesign verification passed. Entitlements remain App Sandbox plus outbound network client only. |
| Approved-target live smoke | PASS — after the redirect fix, the final rebuilt and signed app read the allowlisted operational IPM Class Time target successfully: 92 expanded meetings and 0 cancellation flags. No private row content was recorded. |
| Idempotence | PASS — synthetic repeat/deduplication tests pass, and real aggregate-only reads remain stable at 92/0. Transactional persistence and two-snapshot deletion evidence remain outside Stage 04. |

## Commands and results

```sh
swift package clean && swift build --jobs 1
# PASS: Build complete

./scripts/test.sh
# PASS: 58 tests in 6 suites; SIweb 22 tests

./scripts/test.sh --filter SIwebConnectorTests
# PASS: production URLSession redirect probe and all SIweb tests

./scripts/build-app.sh
./scripts/verify-app.sh
# PASS: signed application built, launched, and completed Keychain identity check

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-authenticate
# PASS: user-established MPU SIweb authorization saved in Keychain

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-smoke-test
# PASS after final rebuild/signing: 92 meetings, 0 cancelled (aggregate output only)

! rg -n 'httpMethod[[:space:]]*=[[:space:]]*"(POST|PUT|PATCH|DELETE)"|uploadTask|dataTask[[:space:]]*\([^)]*from:' Sources/CampusDashboard/Connectors/SIweb
! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '^import (EventKit|UserNotifications|ServiceManagement)|EKEventStore|UNUserNotificationCenter|OpenAI|Anthropic' Sources Tests
plutil -lint Resources/Info.plist Resources/CampusDashboard.entitlements
codesign --verify --deep --strict "dist/Campus Dashboard.app"
codesign -d --entitlements - "dist/Campus Dashboard.app"
git diff --check
# PASS: all scans/checks
```

## Manual and real-service evidence

- MPU Student Home visibly identified Lecture Information → Class Time. The published `wapps2.mpu.edu.mo` entry is an interactive navigation boundary; its authorized flow reaches the operational `wapps2.ipm.edu.mo` service. The GET wrapper embeds `/siweb_cas/time_stud.asp`; the embedded page contains no forms and is the only crawler target.
- The observed target contract has 14 columns: semester, class code, learning module, instructor, venue, period, time, and Sunday through Saturday. Full and continuation row shapes were implemented without retaining a real response fixture.
- The signed app's interactive authorization completed through the ordinary MPU SSO flow. No SSO/MFA/CAPTCHA bypass, browser-cookie extraction, password capture, or state-changing request was used.
- The final signed binary with transport-level redirect refusal performed the mandatory approved-target read successfully. Acceptance evidence records aggregates only; no student identifier, name, class/module title, instructor, venue, date, response body, screenshot, or session material is included.
- The temporary `sessionDataKey` from the originally supplied login URL was not persisted or used as crawler configuration.

## Remaining limitations

- MPU's separate Class Cancellations & Make-up page requires a POST filter form. Stage 04 intentionally does not submit it. Cancellation is parsed where present in the generic contract, but the approved Class Time target exposes no cancellation field; the live result therefore reports zero flags, not a claim that no external cancellation notice exists.
- The connector stops rather than guessing if MPU changes the exact table headers, row shape, date/time format, weekday marker, target origin/path, or login behavior. The target-specific parser must then be versioned and re-accepted.
- The project-wide default target cadence remains hourly while the user is logged in and the Mac can run. Stage 04 supplies only the rate-limited read boundary and implements no scheduler; background scheduling and recovery remain owned by Stage 07.
- A user-established SIweb session can expire or be revoked. Re-run `--siweb-authenticate`; never pass cookie/session values through chat, command-line arguments, source, logs, or fixtures.

## Handoff conclusion

All mandatory Stage 04 automated checks and the available real approved-target read-only smoke test passed. Stage 04 is marked `PASS`; only the main project conversation may accept it and authorize a dependent stage.
