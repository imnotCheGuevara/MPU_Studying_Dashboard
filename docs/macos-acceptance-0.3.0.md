# Campus Dashboard macOS 0.3.0 acceptance

Decision date: 2026-09-12 (Asia/Macau)

Verdict: **ACCEPTED**

## Accepted artifact

- App: `dist/Campus Dashboard.app`
- Version/build: `0.3.0 (4)`
- Bundle identifier: `com.campusdashboard.desktop`
- Executable SHA-256: `d5ee7a4f549bf96cc5c14044351df8e19d3cc035259158ac9e2cea59d174d682`
- CDHash: `71028af713336555023cab26bed328003ac78157`
- Signature: ad hoc; `codesign --verify --deep --strict` passed
- Acceptance host: macOS 26.6.2 (25G83)

## Evidence summary

- Outlook integration was removed from product code, settings, tests, assessment, and active planning. Source, test, and release-executable scans found no Outlook, Microsoft Graph, Graph endpoint, or `Mail.Read` path.
- Automated gate passed after removal: 239 tests across 20 suites, production build, app verification, strict signing, diff check, and targeted safety scans.
- Current signed-app read-only source checks passed:
  - Canvas: 6 courses, 7 tasks, 10 announcements.
  - SIweb: 92 meetings, 0 cancelled.
- The app-owned iCloud calendar was verified. A real schedule cancellation was first previewed without a write, then confirmed only after exact user approval, and restored only after a separate undo approval.
- Final Calendar evidence: one exact meeting binding to one synced app-owned event; signal state `undone / resolved`; outbox `97 completed / 0 pending`.
- Existing signed bilingual/accessibility checks, live settings/recovery inspection, provider-boundary checks, and recent roughly hourly production-run evidence satisfy the release-readiness gates.
- The exact production process was relaunched from the accepted bundle and remained running without a startup crash.

## Safety boundaries retained

- Canvas and SIweb are read-only. The app never submits or changes school data.
- Secrets stay in macOS Keychain and never enter source, SQLite, logs, diagnostics, screenshots, commands, commits, or handoffs.
- Calendar writes are limited to app-owned bound events in the dedicated Campus Dashboard calendar. Each future inferred-date or Calendar change still requires its own confirmation.
- DeepSeek remains optional, minimum-disclosure, direct-HTTPS, schema-validated, and separately consented.

## Known limitations

- The app is ad-hoc signed because no Developer ID identity is installed. Rebuilding may change the macOS code requirement and trigger another Calendar permission grant. A stable external distribution should use a Developer ID signature and notarization.
- iPhone calendar arrival timing is controlled by iCloud after the Mac-side write completes.
- The separate seven-day operational trial (Stage 10) remains paused at day 0 of 7. This acceptance does not claim seven-day reliability evidence.
- Windows is a separate distribution track and is not covered by this macOS verdict.
