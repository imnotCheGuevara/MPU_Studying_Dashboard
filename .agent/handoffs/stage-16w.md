# Stage 16W handoff — Windows application port

Status: `PARTIAL`

Updated: 2026-09-13 Asia/Macau

## Main-conversation approval — 2026-09-12

The user explicitly approved the recommended Windows adaptation defaults. Stage 16W resumed with Windows 11 x64, portable ZIP first, in-app reminders for the beta, no automatic macOS data or credential migration, and no iCloud or substitute external-calendar integration. Pre-approval implementation evidence must be revalidated after this approval.

## Main-conversation pause — 2026-09-12

The user required a Windows adaptation explanation before implementation continued. Stage 16W was paused and commits `101e014` and `40f30f0` were preserved as unreviewed work. This gate was satisfied by the explicit approval recorded above.

## Current slice

The reuse-first Windows track is authorized on `codex/windows-port`. The first slice adds a host-conditional SwiftPM target named `CampusDashboardWindows`, compiling the existing `Domain/Models.swift` and `Fixtures/SyntheticFixtures.swift` directly with a small SwiftCrossUI/WinUI entry point. The accepted macOS package remains the active manifest branch on macOS.

Windows navigation currently provides the intended six in-app surfaces: Today, Schedule, Tasks, Announcements, Needs Review, and Settings. The app clearly labels synthetic preview data until Canvas is configured, maps successful read-only Canvas results into the shared domain snapshot, and persists the last successful normalized snapshot across restarts in `%LOCALAPPDATA%\CampusDashboard\snapshot-v1.json`. The Windows target has no EventKit, iCloud, Outlook/Graph, CalDAV, or external-calendar dependency or control.

The Windows UI is localized in English and Simplified Chinese, selects a supported system language on first launch, and persists the user's Settings choice. Today now shows foreground-only in-app reminders for incomplete tasks due within seven days. Official dates win; suggested dates are eligible only after explicit confirmation. This beta does not register an operating-system notification or background polling service.

## Reuse decision

- UI dependency: `moreSwift/swift-cross-ui` pinned to `0.9.0`; its `DefaultBackend` selects native WinUI on Windows.
- Reused unchanged in this slice: canonical domain models, placeholder visibility semantics, and deterministic populated fixture.
- New platform code: a thin launcher, one Windows UI/state/mapper boundary, Windows Credential Manager storage, atomic JSON snapshot storage, localized copy, a safe foreground reminder engine, focused Windows tests, and one Windows CI workflow.
- Reused Canvas code: configuration, DTOs, concurrency gate, API connector, and snapshot loader remain read-only and feed the shared domain model.
- Still deferred: SIweb authorization, the complete shared SQLite store, DeepSeek, native/background notification behavior, physical-machine accessibility verification, and a signed installer.

## Verification completed

```text
swift package dump-package
PASS — macOS manifest resolves.

swift build
PASS — existing macOS executable builds with the inactive Windows source present.

./scripts/test.sh
PASS — 244 tests in 20 suites after the Windows snapshot, localization, and reminder changes.

swift build -c release
PASS — accepted macOS executable remains buildable with the inactive Windows sources present.

swiftc -parse -target x86_64-unknown-windows-msvc <Windows sources and tests>
PASS — the current Windows-only source and focused test syntax parse for the Windows target.

git diff --check
PASS.
```

Post-approval Windows Server 2022 CI passed at commit `4ac2f5c` in [run 34755547052](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34755547052): dependency resolution, release build, native Windows tests, packaging-tool resolution/build, Swift build-cache save, portable bundling, checksum generation, and artifact upload all passed. The packaging workflow reuses the tested release product while allowing the pinned bundler to prepare the SwiftWinUI-declared Windows App Runtime dependency.

The downloaded artifact wrapper and inner portable ZIP both passed archive integrity checks. The inner ZIP contains 20 files, including `CampusDashboard.exe`, its Swift/VC dynamic libraries, the WinUI bootstrap DLL, and `WindowsAppRuntimeInstaller.exe`. Its SHA-256 is `b17259d95cf1442f0b3b8d7321e75e078279b58fc35bba436af8b4ad09720026`; GitHub reports the same digest for the uploaded release asset.

GitHub prerelease [v0.1.0-windows-preview.1](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/releases/tag/v0.1.0-windows-preview.1) is published with the portable ZIP and `SHA256SUMS.txt`. It is explicitly labeled an unsigned controlled-test build and documents installation, privacy-safe defect reporting, the real-machine smoke matrix, and deferred functionality. No live Canvas, SIweb, DeepSeek, Calendar, or notification operation was performed during CI or artifact inspection.

Post-preview implementation commits add restart-safe Canvas snapshot persistence (`6d878ef`), complete English/Simplified Chinese UI selection and copy (`b333e86`), and safe foreground in-app reminders (`4c9aab6`). The documentation commit `7a3c966` adds `docs/windows-preview-testing.md` with checksum, setup, upgrade, uninstall, data-location, privacy, diagnostic, and physical-machine test instructions. Windows Server 2022 run [34761647634](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34761647634) is still running for the latest functional commit; it is not yet acceptance evidence. Preview 2 must use and verify that run's artifact rather than reusing the older binary.

## Remaining acceptance work

1. Wait for run `34761647634`, download and inspect its artifact, verify the inner ZIP and SHA-256, then publish Preview 2 with the current limitations stated explicitly.
2. Pass the user's real Windows-machine launch, Canvas source, restart, credential, navigation, scaling, keyboard, localization, foreground-reminder, offline, clear-data, and privacy smoke using Preview 2.
3. Reuse compatible SIweb, AI, full persistence, native/background reminders, and presentation/accessibility behavior behind explicit platform boundaries before daily-use acceptance.

Stage 16W cannot be marked `PASS` until the Windows CI artifact and real Windows acceptance matrix pass.
