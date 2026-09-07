# Stage 10R — Pre-trial UI and Simplified Chinese repair

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-10.md for the acceptance-affecting feedback.

## Prerequisite gate

Stage 09 must be accepted, Stage 10 paused, and Stage 10R authorized. Confirm the exact current state in `.agent/CURRENT.md`; if the gate is not met, stop without implementation.

## Stage contract

You own Stage 10R only: the acceptance-affecting production UI and Simplified Chinese repair required before the Stage 10 seven-day trial may restart.

Use the current production database-backed UI created by the ST10-002 repair. Do not return to Stage 01 fixture-driven production behavior. Implement the three linked field-feedback items as one coherent macOS UI system:

1. Redesign Today so its primary content is the current weekly timetable. Columns are Monday through Sunday; the vertical axis is real morning-to-evening time. Course blocks use proportional start, end, and duration placement. Deterministically place overlaps side by side, safely clip out-of-range times, highlight today/current time, and provide previous/next/current-week navigation. Put unread announcements in a right sidebar with course, publication time, source link, and local read action. Keep source/background/refresh status compact and secondary.
2. Redesign Schedule as a spatial macOS calendar experience with day, week, and month modes, previous/next/today navigation, date headers, an all-day area, time gutter, current-time indicator, proportional event blocks, overlap lanes, filters, selection/details, and source links. Distinguish courses, official deadlines, and confirmed inferred deadlines. Do not show unconfirmed inference as a formal event. Follow familiar macOS conventions without copying Apple trademarks, proprietary artwork, private assets, or a pixel-identical Apple Calendar UI.
3. Complete English and Simplified Chinese localization for app-owned UI. Switching language updates dates, weekdays, months, relative time, navigation, status, errors, sync explanations, buttons, menus, dialogs, tooltips, accessibility labels, and empty states. Do not expose raw enum values or English-only error descriptions. Keep source-owned course names/codes, task and announcement titles/bodies, teacher descriptions, locations, and source links exactly as received; never pretend they were translated.

Allowed implementation scope:
- Sources/CampusDashboard/App, Features, and presentation/localization utilities.
- Narrow reusable timetable/calendar layout models or algorithms under an appropriate UI/domain presentation folder.
- Dashboard read models only where required to present existing unified data correctly.
- Tests/CampusDashboardTests additions/updates for Stage 10R.
- README or non-contract implementation documentation when necessary.
- .agent/handoffs/stage-10r.md only.

Do not change connectors, source authorization, sync/deletion semantics, SQLite schema, Calendar ownership/deletion rules, notification policy, AI confirmation policy, privacy clearing, central planning files, accepted handoffs, or .agent/handoffs/stage-10.md. A narrowly necessary compatibility change outside the preferred scope must be documented and regression-tested. Do not ask Stage 01 or Stage 09 tasks to make changes. Do not begin or resume the seven-day trial and do not begin Phase 2.

Required automated acceptance:
- Deterministic layout tests cover proportional vertical placement, duration, overlap lane assignment, stable ordering, clipping, current-week navigation, midnight/cross-day input, time zones, and relevant DST boundaries.
- Day/week/month schedule tests cover date-range calculation, month-grid boundaries, filters, event selection/details, all-day handling, and exclusion of unconfirmed inferred dates.
- Today tests prove Monday-through-Sunday structure, unread-announcement sidebar behavior, local read persistence, and real database data with no fixture fallback.
- Localization coverage tests cover every app-owned user-facing string in English and Simplified Chinese, including enum/status/error mappings, menus, dialogs, help text, accessibility labels, and empty states.
- Locale tests prove Chinese dates/weekdays/months render in Simplified Chinese and English renders in English using the intended time zone.
- Source-preservation tests prove language switching does not alter source-owned course/task/announcement/location text or source URLs.
- Existing data, sync, Calendar, notification, AI, privacy, and security suites remain passing.

Required manual visual and interaction acceptance on the final signed app:
- Inspect Today and Schedule at 1180x780 and the 980x680 minimum window size, in both English and Simplified Chinese; verify no clipped essential controls, unreadable overlaps, or inaccessible right sidebar.
- Verify representative overlapping and adjacent classes, an empty day, a seven-day week boundary, month boundary, current-time marker, long titles, and empty/error/permission states using synthetic or irreversibly sanitized QA data.
- Verify day/week/month navigation, Today/current-week actions, filters, event detail/source-link interaction, announcement read action, keyboard focus, and accessibility labels.
- Verify the production signed app still renders database-backed records and contains no Stage 01 fixture fallback or synthetic-production banner. Do not store screenshots containing private school content.

Verification before handoff:
- Run focused Stage 10R tests during development.
- Run the complete test suite once final, then clean debug build, release app build, app verification, codesign verification, plist/entitlement validation, credential scan, fixture-leak scan, and localization coverage scan.
- Keep successful verbose logs in a temporary directory and record concise exact results. Show complete relevant failure details.

Write .agent/handoffs/stage-10r.md with PASS, PARTIAL, or BLOCKED; changed files; design/layout decisions; localization inventory and source-text boundary; exact test/build/scan results; manual visual evidence for both languages and window sizes; accessibility/keyboard evidence; remaining risks; and confirmation that Stage 10 was not resumed. Never mark PASS if any required view, language, layout edge, or final signed-app check was skipped.
