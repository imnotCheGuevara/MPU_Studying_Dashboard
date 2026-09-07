# Canvas connector assessment

Status: repaired implementation passes offline acceptance and the final repaired signed build passes the real read-only smoke.

## Access decision

The connector uses Canvas REST API version 1 over HTTPS and never scrapes Canvas pages. It accepts a bearer access token only through the existing macOS Keychain boundary. OAuth-issued access tokens and institution-approved personal access tokens use the same runtime bearer-token storage; this stage does not implement an OAuth browser flow. A personal access token is permitted only when the institution explicitly allows it. Revocation occurs in Canvas and local removal occurs through Keychain; no refresh-token flow is claimed.

The institution name, instance URL, token, token lifetime, and account identifiers are intentionally not recorded. The user locally confirmed and supplied the institution-approved configuration through the no-echo/Keychain flow.

The minimum read-only API scopes, when scoped tokens are supported by the institution, correspond to these GET routes:

- `/api/v1/courses`
- `/api/v1/courses/:course_id/assignments`
- `/api/v1/courses/:course_id/discussion_topics` with `only_announcements=true`

No POST, PUT, PATCH, or DELETE route exists in the connector.

## Fields and mapping

Canvas DTOs are private to `Connectors/Canvas`. They map to connector records in `CanvasService`; UI and domain layers never receive a Canvas response object.

| Record | Canvas fields used | Connector behavior |
| --- | --- | --- |
| Course | `id`, `name`, `course_code`, `term.name`, `time_zone`, `html_url` | Requests active, available student enrollments; stable source ID is Canvas `id`. |
| Task | `id`, `course_id`, `name`, `due_at`, `unlock_at`, `lock_at`, `html_url`, `submission_types`, `quiz_id`, `is_quiz_assignment`, external-tool URL, `has_overrides` | Sends `override_assignment_dates=true`. Canvas documents `due_at`, `unlock_at`, and `lock_at` as the dates effective for the requesting user. `has_overrides` maps to `hasAssignmentOverrides`, meaning only that the assignment has at least one override; it does not claim the requesting user's effective dates came from one. Undated tasks remain undated. `all_dates` is neither requested nor carried across the connector boundary. |
| Announcement | `id`, `context_code`, `title`, `message`, `posted_at`, `delayed_post_at`, `updated_at`, `html_url` | Reads announcement discussion topics per course. HTML is reduced to a bounded plain-text summary; no full response body is logged. |

Quiz-like classification is deterministic: `quiz_id` or `online_quiz` is Classic Quiz; an external-tool assignment explicitly marked as a quiz or exposing a New Quiz/quiz-LTI URL is New Quiz; other external-tool assignments remain `external_tool`. The connector does not retrieve questions, answers, attempts, submissions, or grades.

## Pagination, throttling, and retries

- `per_page=100` is a request preference, not a completeness assumption. The connector follows `rel="next"` in Canvas's `Link` header until absent.
- A next link must remain HTTPS, on the configured origin and port, and below the configured `/api/v1/` path. Cross-origin or non-API links fail closed.
- Snapshot collection rejects repeated tokens and more than 1,000 pages per collection.
- Every transport attempt passes through a dedicated cancellation-safe asynchronous permit gate. The production default is one concurrent request and the limit is injectable. Actor isolation is not treated as the bound because actor methods can reenter across `await`.
- `X-Rate-Limit-Remaining` and `X-Request-Cost` are retained as numeric connector state without account identifiers.
- A request and resource timeout of 30 seconds is applied.
- 401 and 403 do not retry. 404 is a terminal visibility/not-found error. 429 and 5xx retry up to three total attempts. Numeric `Retry-After` is used exactly and bypasses jitter. Without it, delay is `min(cap, exponential × multiplier)` with an injected multiplier clamped to `0.5...1.5`; production randomness and deterministic test sequences use the same boundary. Timeout, offline, connection loss, DNS, and connection failures are explicitly classified; transient network errors use the same bound.

Official Canvas references: [Assignments](https://developerdocs.instructure.com/services/canvas/resources/assignments), [Discussion topics](https://developerdocs.instructure.com/services/canvas/resources/discussion_topics), [Pagination](https://developerdocs.instructure.com/services/canvas/basics/file.pagination), and [Throttling](https://developerdocs.instructure.com/services/canvas/basics/file.throttling).

## Snapshot and deletion semantics

The connector can collect a complete paginated read snapshot and deduplicates within that result by stable source ID. Repeating the same sanitized fixture snapshot produces the same records and no duplicates. It performs no persistence transaction, incremental cursor management, deletion inference, or cross-source scheduling; those belong to Stage 05.

A missing item from one read is never cancellation evidence. The later sync engine must apply the project rule requiring an explicit source state or two complete successful snapshots before a soft deletion. Course, task, and announcement source links are retained for lawful user navigation but are excluded from diagnostics.

## Secure setup and diagnostics

`--canvas-configure` validates the HTTPS base URL before requesting authorization, then obtains the access token through macOS `readpassphrase` with echo disabled and an interactive-TTY requirement. It fails closed rather than falling back to visible input. The temporary C buffer is cleared after copying the value for Keychain storage. The URL is stored in app preferences and the token is stored under service `com.campusdashboard.desktop.canvas` in macOS Keychain. An explicit reconfiguration recreates the Keychain item so local ad-hoc rebuilds do not retain an obsolete code-signing ACL. Neither value is accepted as a command argument.

`--canvas-smoke-test` loads that configuration and performs only the three GET collections above. Output is limited to aggregate counts or an error category. Connector diagnostics never include authorization headers, response bodies, full URLs, account/course/object identifiers, or personal content.

Synthetic fixtures use reserved `.invalid` hosts and fictional IDs/content. Ordinary automated tests never contact Canvas.

## Real validation result

The final repaired signed app completed the course collection, each returned course's assignment collection, and each returned course's announcement collection without recording private response data. Aggregate result: 6 courses, 0 tasks, and 5 announcements. The zero-task result means real Classic/New Quiz field variants were not present to observe during this run; sanitized fixtures remain the evidence for those mappings. The user confirmed that the earlier exposed authorization was revoked and rotated, and final authorization was supplied through hidden input. No URL, token, ID, title, or response body is recorded.
