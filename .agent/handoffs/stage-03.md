# Stage 03 handoff

Status: PASS

## Scope delivered

- Added a read-only Canvas REST API connector implementing the existing `CanvasService` contract. Canvas DTOs remain inside `Connectors/Canvas` and map to connector records before crossing the service boundary.
- Added current-student course reads with stable Canvas IDs, course code, term, time zone, and source link.
- Added assignment reads with `override_assignment_dates=true` and uses Canvas's `due_at`, `unlock_at`, and `lock_at` as requesting-user-effective dates. `has_overrides` maps to `hasAssignmentOverrides`, which means only that the assignment has at least one override and does not assert that the current user's dates came from one. `all_dates` is neither requested nor carried across the connector boundary. Undated items remain undated.
- Added deterministic classification for ordinary assignments, Classic Quiz, New Quiz when exposed as a quiz-marked/quiz-LTI external tool, and other external-tool items.
- Added per-course announcement reads using discussion topics with `only_announcements=true`, including title, publication/update time, bounded plain-text summary, stable ID, course context, and source link.
- Added same-origin `Link` pagination validation, repeated-token and 1,000-page safety bounds, a dedicated cancellation-safe concurrency gate (production limit 1, injectable), 30-second request/resource timeouts, rate-limit header awareness, exact numeric `Retry-After`, capped exponential retry with injected jitter, and explicit 401/403/404/429/5xx/network/error-format classifications.
- Added a connector-only snapshot collector that performs no persistence, deletion inference, global scheduling, or downstream side effects and deduplicates stable IDs deterministically.
- Added secure local configuration through a signed-app command mode: the HTTPS base URL is validated before authorization is requested, while `readpassphrase` with echo disabled and an interactive-TTY requirement sends token input directly to macOS Keychain. Neither value is accepted as a command-line argument. The read-only smoke mode prints aggregate counts or a redacted category only.
- Added an implementation/connection assessment covering authorization assumptions, scopes/routes, fields, effective override behavior, pagination, throttling, timeouts, retries, deletion limits, diagnostics, and the remaining institutional validation.
- Added fully fictional sanitized JSON fixtures on reserved `.invalid` hosts and thirteen Canvas connector tests. The complete suite now contains 36 tests in five suites.

## Changed files

- `Package.swift`
- `README.md`
- `Sources/CampusDashboard/App/CampusDashboardApp.swift`
- `Sources/CampusDashboard/Services/ServiceContracts.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasAPIConnector.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasConcurrencyGate.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasConfiguration.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasDTOs.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasLocalTool.swift`
- `Sources/CampusDashboard/Connectors/Canvas/CanvasSnapshotLoader.swift`
- `Tests/CampusDashboardTests/CanvasConnectorTests.swift`
- `Tests/CampusDashboardTests/Fixtures/Canvas/courses-page-1.json`
- `Tests/CampusDashboardTests/Fixtures/Canvas/courses-page-2.json`
- `Tests/CampusDashboardTests/Fixtures/Canvas/assignments.json`
- `Tests/CampusDashboardTests/Fixtures/Canvas/announcements.json`
- `Tests/CampusDashboardTests/Fixtures/Canvas/malformed.json`
- `docs/canvas-connector.md`
- `.agent/handoffs/stage-03.md`

No project constraint, roadmap, status, stage prompt, project specification, or earlier-stage handoff was edited.

## Acceptance evidence

| Acceptance item | Evidence/result |
| --- | --- |
| Clean build succeeds | PASS — `swift package clean && swift build --jobs 1` completed with `Build complete!`. |
| Automated tests pass | PASS — the repaired suite runs 36 tests in five suites. Thirteen Canvas tests cover two-page `Link` pagination, same-origin enforcement, current-user effective dates, accurate override-presence metadata, undated tasks, Classic Quiz, New Quiz, non-quiz external tools, announcements, malformed responses, status/retry categories, timeout, rate headers, redaction, GET-only behavior, duplicate-free repeated fixtures, controlled transport concurrency, cancellation safety, and deterministic jittered backoff. |
| Current-user courses and context map without Canvas DTO leakage | PASS — course fixtures decode numeric/string stable IDs and context fields into `CanvasCoursePayload`; connector DTOs are confined to the connector folder and service output types are source-boundary records. |
| Effective assignment and override semantics | PASS — the request explicitly sends `override_assignment_dates=true`; the response's `due_at` is used as the requesting-user-effective value. Fixture `has_overrides=true` maps only to `hasAssignmentOverrides=true`. The inaccurate current-user-override boolean and unused `all_dates` request/claims were removed. |
| Quiz-like items and undated work | PASS — fixture tests separately verify Classic Quiz, New Quiz exposed through external-tool quiz metadata, a non-quiz external tool, an ordinary assignment, and a nil due date. No question, answer, submission, or grade endpoint exists. |
| Announcements | PASS — per-course read uses `only_announcements=true`; fixture test verifies course context, stable ID, publish/update dates, source link mapping, and HTML-to-bounded-text summary. |
| Pagination, concurrency, rate limit, timeout, and retry rules | PASS — safe `rel="next"` parsing, origin/API-path checks, loop/page bounds, 30-second URLSession limits, numeric rate headers, and explicit gate/backoff tests are present. Eight simultaneous calls against a blocked transport with limit 2 started exactly two network calls before release and never exceeded peak 2. A queued cancellation did not start work or leak its permit. No-`Retry-After` delays used injected multipliers and matched `[0.5, 3, 6, 8, 8]`; server delay bypassed jitter. |
| Errors and diagnostics are classified/redacted | PASS — diagnostics contain only a category and optional HTTP status. Tests inject private response/token markers and verify they, the response body, and host URL never appear. Repository credential scan passed. |
| Repeating fixture import creates no duplicates | PASS — the snapshot test deliberately duplicates each sanitized course/task/announcement record, runs the import twice, and verifies identical output with one course, five tasks, and one announcement. |
| Connector performs no Canvas write request | PASS — all three connector routes set `GET`, have no body, and the request test verifies this. A source scan found no Canvas POST/PUT/PATCH/DELETE, upload task, or body-upload call. |
| Signed app and secure local authorization entry work | PASS after repair — `./scripts/build-app.sh` produced and signed the release app; `./scripts/verify-app.sh` launched it and completed its packaged-identity Keychain smoke test. A user run exposed that the earlier `getpass` path could visibly fall back in this environment. It was replaced by `readpassphrase` using `RPP_ECHO_OFF | RPP_REQUIRE_TTY`, URL validation now occurs before the authorization prompt, and a pseudo-terminal check accepted a 22-character synthetic value without returning it in output. |
| Minimal real read-only Canvas smoke test | PASS — after one redacted `unauthorized` attempt and another hidden reconfiguration, the final repaired signed build's `--canvas-smoke-test` exited 0. It completed course collection plus assignment and announcement collection for every returned course. Privacy-safe aggregates were 6 courses, 0 tasks, and 5 announcements; no URL, token, ID, title, or response body was recorded. |
| Exposed-token revocation/rotation | PASS — in direct response to the explicit revocation/rotation and final hidden-configuration checklist, the user confirmed completion. No credential value was requested or recorded. |
| Future-stage scope remains absent | PASS — no SIweb adapter, global sync engine, EventKit, notifications, background scheduling, or AI implementation was added. The future-system symbol scan passed. |

## Commands run

```sh
swift build --jobs 1
./scripts/test.sh

swift package clean
swift build --jobs 1
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh

for run_index in {1..20}; do
  ./scripts/test.sh --filter CanvasConnectorTests
done

"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --canvas-smoke-test
# Pre-repair privacy-safe result: PASS; 6 courses, 0 tasks, 5 announcements; exit 0.
# Final repaired build attempt: unauthorized; exit 3. No response body was recorded.
# Final repaired build result: PASS; 6 courses, 0 tasks, 5 announcements; exit 0.

codesign --verify --deep --strict "dist/Campus Dashboard.app"

! rg -n 'httpMethod[[:space:]]*=[[:space:]]*"(POST|PUT|PATCH|DELETE)"|uploadTask|dataTask[[:space:]]*\([^)]*from:' Sources/CampusDashboard/Connectors/Canvas
! rg -n '(^|[^A-Za-z])sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~+/-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|client[_-]?secret[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|password[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----' --hidden --glob '!.git/**' --glob '!.build/**' --glob '!dist/**' .
! rg -n '^import (EventKit|UserNotifications|ServiceManagement)|EKEventStore|UNUserNotificationCenter|OpenAI|Anthropic' Sources Tests
git diff --check
git status --short
```

## Manual and integration checks

- The final repaired release app retained the expected signed identity and completed the Stage 02 packaged Keychain lifecycle smoke test.
- No real Canvas response body, URL, account identifier, course identifier/title, or authorization was captured in output or this handoff.
- A user-provided terminal screenshot showed that an authorization value had become visible during the original configuration flow. The value is intentionally not copied here. The input path was repaired and verified with a pseudo-terminal, and the user was instructed to revoke and rotate the exposed value. Explicit user confirmation remains pending.
- A later smoke attempt found the URL and Keychain item present but returned the redacted `configuration` category before networking. The local ad-hoc rebuild had retained the earlier item's obsolete code-signing ACL through `SecItemUpdate`. Explicit reconfiguration now recreates the item so the currently signed application owns its ACL; another no-echo reconfiguration is required before repeating the live smoke.
- Before this concurrency/retry/semantics repair, a reconfigured signed build completed a real read-only smoke across all three collection paths and emitted only aggregate counts. Because the final repair rebuilt and re-signed the app, that earlier result is retained as history but does not satisfy the final post-repair smoke requirement.
- The user then confirmed exposed-token revocation/rotation and hidden configuration of the final build. Its first final smoke reached Canvas but received the redacted `unauthorized` category, so it did not retry and PASS remained prohibited at that point.
- After another hidden configuration with an active replacement token, the same final repaired signed build completed the real read-only smoke successfully. Only aggregate counts were emitted.

## Remaining limitations

The final live account returned zero current task records, so the real smoke did not expose a live Classic Quiz, New Quiz, external-tool item, undated assignment, or effective override. Their decoding and classification evidence is the passing sanitized fixture suite. The final assignment endpoint was called successfully for every returned course and returned valid empty collections.

No mandatory Stage 03 acceptance item remains skipped. The main project conversation must still inspect this repaired handoff and explicitly accept Stage 03 before it can satisfy a Stage 05 dependency.
