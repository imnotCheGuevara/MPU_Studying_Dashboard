# Stage 16W handoff — Windows application port

Status: `PARTIAL`

Updated: 2026-09-12 Asia/Macau

## Main-conversation approval — 2026-09-12

The user explicitly approved the recommended Windows adaptation defaults. Stage 16W resumed with Windows 11 x64, portable ZIP first, in-app reminders for the beta, no automatic macOS data or credential migration, and no iCloud or substitute external-calendar integration. Pre-approval implementation evidence must be revalidated after this approval.

## Main-conversation pause — 2026-09-12

The user required a Windows adaptation explanation before implementation continued. Stage 16W was paused and commits `101e014` and `40f30f0` were preserved as unreviewed work. This gate was satisfied by the explicit approval recorded above.

## Current slice

The reuse-first Windows track is authorized on `codex/windows-port`. The first slice adds a host-conditional SwiftPM target named `CampusDashboardWindows`, compiling the existing `Domain/Models.swift` and `Fixtures/SyntheticFixtures.swift` directly with a small SwiftCrossUI/WinUI entry point. The accepted macOS package remains the active manifest branch on macOS.

Windows navigation currently proves the intended six in-app surfaces with synthetic data: Today, Schedule, Tasks, Announcements, Needs Review, and Settings. The Windows target has no EventKit, iCloud, Outlook/Graph, CalDAV, or external-calendar dependency or control.

## Reuse decision

- UI dependency: `moreSwift/swift-cross-ui` pinned to `0.9.0`; its `DefaultBackend` selects native WinUI on Windows.
- Reused unchanged in this slice: canonical domain models, placeholder visibility semantics, and deterministic populated fixture.
- New platform code: a thin launcher, one Windows UI/state/mapper boundary, Windows Credential Manager storage, focused Windows tests, and one Windows CI workflow.
- Reused Canvas code: configuration, DTOs, concurrency gate, API connector, and snapshot loader remain read-only and feed the shared domain model.
- Still deferred: SIweb authorization, SQLite persistence, DeepSeek, reminders/background behavior, full localization/accessibility, and a signed installer.

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

Pre-approval Windows CI proved the release executable and native Windows tests, including Credential Manager create/read/delete. Packaging remained blocked only because the bundler subprocess did not receive the Swift executable path; the post-approval fix supplies the resolved toolchain explicitly and packages only the approved portable ZIP. No live Canvas, SIweb, DeepSeek, Calendar, or notification operation was performed.

## Remaining acceptance work

1. Pass the post-approval Windows 2022 build, tests, and portable bundle job; record its run and artifact hash.
2. Publish the portable ZIP as a GitHub prerelease for the controlled real-machine smoke.
3. Pass the user's real Windows-machine launch, Canvas source, restart, credential, navigation, scaling, keyboard, and privacy smoke.
4. Reuse compatible persistence, SIweb, AI, reminders, localization, and presentation code behind explicit platform boundaries before daily-use acceptance.

Stage 16W cannot be marked `PASS` until the Windows CI artifact and real Windows acceptance matrix pass.
