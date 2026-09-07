# SIweb read-only connector assessment

Status: Stage 04 implementation and authenticated aggregate-only acceptance complete.

## MPU target assessment (2026-08-31)

- School/system: Macao Polytechnic University (MPU), Student Information Web Portal (SIWeb).
- MPU publishes the SIWeb entry as `https://wapps2.mpu.edu.mo/siweb_cas/`. That public MPU-domain entry is used only to begin interactive navigation; it passes through MPU SSO at `https://account.ipm.edu.mo/authenticationendpoint/login.do` and the authorized service operates on the legacy IPM domain.
- The login page identifies itself as MPU Single Sign-On. Authentication is performed personally by the user inside the signed application's non-persistent web view; the crawler does not read or submit the login form.
- A session-key-free reconstruction of the CAS parameters reaches the same login form. The `sessionDataKey` embedded in a copied login URL is temporary authorization-flow state and must never be persisted as the SIweb base URL or a target page.
- After successful SSO, the Student Home page links Lecture Information → Class Time to `https://wapps2.ipm.edu.mo/siweb_cas/siweb_sa.asp?bookmark=time_stud`. That GET-only wrapper embeds the approved read-only target `/siweb_cas/time_stud.asp`.
- The Class Time result contains no forms. MPU's separate Class Cancellations & Make-up page uses a POST filter form, so Stage 04 deliberately does not automate or submit it.

Current route decision: the only production crawler target is `https://wapps2.ipm.edu.mo/siweb_cas/time_stud.asp`, under operational base `https://wapps2.ipm.edu.mo/siweb_cas`. The published `wapps2.mpu.edu.mo` entry, `account.ipm.edu.mo` SSO, and Banner Student Home are authentication/navigation boundaries, not crawler targets.

## Admission decision

The connector is a conditional Go only for an explicitly approved HTTPS origin and an explicit list of schedule pages. It does not discover or crawl links outside that list. It sends only `GET` requests with no body and has no form-submission, write, SSO, MFA, CAPTCHA, browser-control, or access-control-bypass path.

The production target, app-side authorization flow, and real page contract are now known and tested. No MFA, CAPTCHA, access restriction, or SSO control is bypassed. If MPU later changes the ordinary login flow or disallows automated reads, this route becomes No-Go until an approved API/export is available.

## Authorization and secret boundary

`SIwebSessionAuthorizer` is the narrow session boundary. The production implementation reads an institution-approved session Cookie header from macOS Keychain only when constructing an in-memory request. The URLSession is ephemeral, has cookie persistence disabled, does not cache responses, and refuses every automatic HTTP redirect at its task delegate. Session material is never included in connector errors.

The signed app exposes `--siweb-authenticate`. It opens the published `wapps2.mpu.edu.mo` entry in a non-persistent `WKWebView`; the user enters credentials and completes any institutional challenge directly on MPU's pages. After MPU returns to an authorized Student Home/SIweb page, the app selects only unexpired secure cookies valid for the operational `wapps2.ipm.edu.mo` target, serializes them in memory, and stores the result in macOS Keychain. Cookies scoped only to the published entry or SSO host are rejected. The app does not inspect login fields, copy browser cookies, persist WebKit data, or automate SSO/MFA/CAPTCHA.

## Allowed routes and request policy

- Base and target pages must use HTTPS, contain no URL credentials or fragment, share the exact host/port, and remain beneath the configured base path.
- Every requested page, including a semantic next-page link, must exactly match the configured allowlist. Cross-origin, merely same-prefix, or unlisted pagination fails before transport.
- Requests use `GET`, an empty body, a 30-second default timeout, an ephemeral no-cache session, a default concurrency limit of 1, and a default minimum start interval of 1 second.
- The production URLSession delegate answers every redirect challenge with `nil`. The original 3xx response is returned to the connector for `loginRedirect` classification; no second request is sent and no session Cookie can be forwarded to a redirect target.
- Configuration caps concurrency at 4. The cancellation-safe permit gate bounds in-flight requests, and the reservation-based pacer spaces every network start even while its actor is reentrant.
- HTTP 429 and 5xx plus temporary network failures use capped exponential retry with jitter and honor numeric `Retry-After`. Authentication/authorization, route, parsing, and structural failures do not retry.

## Parser contracts

Parser version `siweb-schedule-v1.0.0` defines the synthetic contract used to test generic safety behavior:

- page marker `data-siweb-contract="schedule-v1"`;
- terminal completeness marker `data-siweb-complete="true"`;
- course ID and name, with optional code;
- meeting ID when present, explicit-offset ISO-8601 start/end, optional location/source link, and `scheduled` or `cancelled` status;
- explicit empty marker for a legitimately empty schedule;
- optional allowlisted next-page link.

An absent meeting ID derives deterministically from course ID, exact start/end strings, and location using a versioned reversible encoding. Titles are never used as identity. Duplicate IDs with conflicting values, unknown statuses, missing required fields, timezone-free dates, invalid intervals, cross-origin links, missing completion markers, and unknown DOM contracts stop the entire page. The connector emits no guessed partial records.

Parser version `mpu-time-stud-v1.0.0` implements the observed MPU Class Time contract. It requires this exact 14-column header: `Sem`, `Class Code`, `Learning Module`, `Instructor`, `Venue`, `Period`, `Time`, `Sun`, `Mon`, `Tue`, `Wed`, `Thu`, `Fri`, `Sat`. A full row supplies all fields; a continuation row must use the observed three-column leading span and inherits semester, class code, and module. `Period` must be `yyyy/MM/dd-yyyy/MM/dd`, `Time` must be `HH:mm-HH:mm`, and teaching weekdays are indicated by `images/dot.gif`. Recurrences are expanded in `Asia/Macau`, bounded, and assigned deterministic versioned IDs. Unknown headers, malformed periods/times, missing weekdays, invalid continuations, excessive ranges, and conflicting identities fail the whole page.

## Parsed boundary fields

The connector boundary provides stable meeting ID, course stable ID, course name/code, start/end instants, original UTC offset identifier, optional location, cancellation state, same-origin source link, parser version, and a SHA-256 hash of the parsed page. It does not retain the complete page, persist data, or infer deletions; Stage 05 owns minimal raw records, normalization, transactions, two-snapshot deletion evidence, and downstream outbox work.

## Failure categories and diagnostics

Errors are categorized as configuration, unsafe route, forbidden/not found, rate limited, server unavailable, timeout/offline/transport, expired session, login redirect, partial response, structural change, or malformed response. Diagnostics contain only the source name and category. Response bodies, configured URLs, cookies, identifiers, course content, and redirect locations are excluded.

HTTP redirects are disabled in the production transport and the original 3xx is treated as a login redirect by the connector. A final response URL different from the requested allowlisted URL is also rejected as defense in depth. A 200 response containing password/login/SSO form markers is classified as session expiry before structural parsing. HTTP 206, oversized bodies, missing terminal completeness, and truncated markup fail as partial responses. A real URLSession regression test uses a loopback HTTP server and proves that only the initial redirecting route is requested and that the redirect destination receives no Cookie.

## Snapshot and deletion semantics

`SIwebSnapshotLoader` follows only allowlisted next-page tokens, rejects loops and more than 100 pages, and deduplicates identical stable IDs. Conflicting duplicate records fail as structural change. The loader does not interpret a missing meeting as deletion or cancellation and does not write persistence, calendar, notification, or source state.

## Live acceptance

Build the signed app, authorize locally without placing session material in shell arguments or chat, and run:

```sh
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-authenticate
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-smoke-test
```

The smoke command prints only aggregate meeting/cancellation counts or a redacted category. The final parser read the approved target successfully and returned 92 expanded meetings and 0 cancellation flags. Four consecutive aggregate-only reads produced the same result. No real identifiers, titles, instructors, venues, dates, response bodies, screenshots, or session material were written to the repository or acceptance record.

Cancellation state remains supported and tested in the synthetic contract. The MPU Class Time target has no cancellation column; the separate cancellation/make-up POST form is outside the approved GET-only target and is not submitted.

The project-wide default target cadence remains hourly while the user is logged in and the Mac can run. Stage 04 supplies only rate-limited connector reads and implements no scheduler; background scheduling and recovery behavior remain owned by Stage 07.
