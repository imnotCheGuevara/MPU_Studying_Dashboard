# Stage 16W handoff — Windows application port

Status: `PARTIAL`

Updated: 2026-09-11 Asia/Macau

## Main-conversation pause — 2026-09-12

The user requires a Windows adaptation explanation for review before any Windows implementation continues. Stage 16W is therefore paused. Draft commits `101e014` and `40f30f0` are preserved unchanged as unreviewed work; they are not accepted Windows evidence. The review-gate commit changes documentation only. Resume only after explicit approval of `docs/windows-adaptation-review.md`.

## Current slice

The reuse-first Windows track is authorized on `codex/windows-port`. The first slice adds a host-conditional SwiftPM target named `CampusDashboardWindows`, compiling the existing `Domain/Models.swift` and `Fixtures/SyntheticFixtures.swift` directly with a small SwiftCrossUI/WinUI entry point. The accepted macOS package remains the active manifest branch on macOS.

Windows navigation currently proves the intended six in-app surfaces with synthetic data: Today, Schedule, Tasks, Announcements, Needs Review, and Settings. The Windows target has no EventKit, iCloud, Outlook/Graph, CalDAV, or external-calendar dependency or control.

## Reuse decision

- UI dependency: `moreSwift/swift-cross-ui` pinned to `0.9.0`; its `DefaultBackend` selects native WinUI on Windows.
- Reused unchanged in this slice: canonical domain models, placeholder visibility semantics, and deterministic populated fixture.
- New platform code: one Windows UI entry file, one Windows-only test file, and one Windows CI workflow.
- Deferred until the Windows build probe passes: larger source/service selection, SQLite compatibility, Windows credential storage, authorized browser login, reminders/background behavior, localization resources, and distributable packaging.

## Verification completed

```text
swift package dump-package
PASS — macOS manifest resolves.

swift build
PASS — existing macOS executable builds with the inactive Windows source present.

./scripts/test.sh
PASS — 239 tests in 20 suites.

git diff --check
PASS.
```

No live Canvas, SIweb, DeepSeek, Calendar, notification, or credential operation was performed.

## Remaining acceptance work

1. Push this slice and obtain a clean `windows-latest` build/test result.
2. Correct any Windows compiler/backend incompatibility before extending the port.
3. Reuse the compatible persistence, connector, AI, and presentation files behind explicit platform boundaries.
4. Implement Windows native credential protection and reminder/background adapters with focused safety tests.
5. Produce a complete Windows package, document its hash, and pass the user's real Windows-machine launch/source/restart smoke.

Stage 16W cannot be marked `PASS` until the Windows CI artifact and real Windows acceptance matrix pass.
