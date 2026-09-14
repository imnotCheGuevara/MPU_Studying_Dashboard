# Stage 16W handoff — Windows application port

Status: `PARTIAL`

Updated: 2026-09-14 Asia/Macau

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

Post-preview implementation commits add restart-safe Canvas snapshot persistence (`6d878ef`), complete English/Simplified Chinese UI selection and copy (`b333e86`), and safe foreground in-app reminders (`4c9aab6`). The documentation commit `7a3c966` adds `docs/windows-preview-testing.md` with checksum, setup, upgrade, uninstall, data-location, privacy, diagnostic, and physical-machine test instructions.

Windows Server 2022 run [34761647634](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34761647634) completed successfully for functional commit `4c9aab69900148ad08804ef71e42eaca0eef3dd7` in 36 minutes 39 seconds. Dependency resolution, Release compilation, Windows tests, packaging-tool resolution, build-cache preparation, portable bundling, and artifact upload all passed. Its unexpired source artifact is `CampusDashboard-Windows-0.1.0`, artifact id `10319558042`, size `114502709` bytes, with GitHub Actions wrapper digest `sha256:a0dbcf06b9c7ff18255b1a4cdd4e8b00920c5db71549d15b1dbc19d8f61e69a5`.

The automated Preview 2 draft workflow was added in `a7b975c` and corrected in `48fa3de` to select that exact artifact by both run id and artifact id. Successful publishing workflow run [34779276068](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34779276068) verified the source commit and artifact metadata, downloaded the exact Windows artifact, passed `sha256sum --check`, passed ZIP integrity and required-file checks, rejected prohibited external-calendar filenames, produced release notes, and created the prerelease draft. The changes from the tested functional commit through `48fa3de` are limited to this handoff, the release workflow, `README.md`, and `docs/windows-preview-testing.md`; no later product source is substituted into the tested package.

GitHub release draft id `388016887` is named `Campus Dashboard Windows Preview 2`, reserves tag `v0.1.0-windows-preview.2`, targets `48fa3def92cdc1c9b3cf3ff3923c56fb6e31a1d1`, and remains `draft: true`, `prerelease: true`, with no publication timestamp. Its two uploaded assets are:

- `CampusDashboard-Windows-0.1.0-portable-x64.zip`: asset id `561833060`, `114920702` bytes, GitHub release-asset digest `sha256:43f1776aa1f9f54a8a9fd4cf1801794007dbddad54967f01629304950c1cce75`;
- `SHA256SUMS.txt`: asset id `561833065`, `114` bytes, GitHub release-asset digest `sha256:df4259e503cf10897edf1990a6300776fec3e0a0c4a4d42a8d80973f2b10d29b`.

The draft body explicitly lists the included learner flow, Canvas read-only and Credential Manager boundaries, restart-safe snapshot, foreground-only reminders, absence of iCloud and every substitute external calendar, privacy-safe testing instructions, and the still-deferred SIweb, DeepSeek, background refresh, native Windows notifications, and signed installer. Publishing the draft is a public GitHub action and is waiting for the user's immediate action-time confirmation.

## Remaining acceptance work

1. After immediate user confirmation, publish the already verified Preview 2 draft without changing its tested assets or stated limitations.
2. Pass the user's real Windows-machine launch, Canvas source, restart, credential, navigation, scaling, keyboard, localization, foreground-reminder, offline, clear-data, and privacy smoke using Preview 2.
3. Reuse compatible SIweb, AI, full persistence, native/background reminders, and presentation/accessibility behavior behind explicit platform boundaries before daily-use acceptance.

Stage 16W cannot be marked `PASS` until the Windows CI artifact and real Windows acceptance matrix pass.
