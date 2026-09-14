# Stage 16W handoff — Windows application port

Status: `PARTIAL`

Updated: 2026-09-14 Asia/Macau

## Main-conversation approval — 2026-09-12

The user explicitly approved the recommended Windows adaptation defaults. Stage 16W resumed with Windows 11 x64, portable ZIP first, in-app reminders for the beta, no automatic macOS data or credential migration, and no iCloud or substitute external-calendar integration. Pre-approval implementation evidence must be revalidated after this approval.

## Main-conversation pause — 2026-09-12

The user required a Windows adaptation explanation before implementation continued. Stage 16W was paused and commits `101e014` and `40f30f0` were preserved as unreviewed work. This gate was satisfied by the explicit approval recorded above.

## Current slice

The reuse-first Windows track is authorized on `codex/windows-port`. The first slice adds a host-conditional SwiftPM target named `CampusDashboardWindows`, compiling the existing `Domain/Models.swift` and `Fixtures/SyntheticFixtures.swift` directly with a small SwiftCrossUI/WinUI entry point. The accepted macOS package remains the active manifest branch on macOS.

Windows navigation currently provides the intended six in-app surfaces: Today, Schedule, Tasks, Announcements, Needs Review, and Settings. The app clearly labels synthetic preview data until a source is configured, maps successful read-only Canvas and SIweb results into the shared domain snapshot, and persists the last successful normalized snapshot across restarts in `%LOCALAPPDATA%\CampusDashboard\snapshot-v1.json`. Canvas and SIweb have separate Windows Credential Manager entries and independent forget actions; forgetting one source preserves the other source's normalized data. The Windows target has no EventKit, iCloud, Outlook/Graph, CalDAV, or external-calendar dependency or control.

The Windows UI is localized in English and Simplified Chinese, selects a supported system language on first launch, and persists the user's Settings choice. Today now shows foreground-only in-app reminders for incomplete tasks due within seven days. Official dates win; suggested dates are eligible only after explicit confirmation. This beta does not register an operating-system notification or background polling service.

## Reuse decision

- UI dependency: `moreSwift/swift-cross-ui` pinned to `0.9.0`; its `DefaultBackend` selects native WinUI on Windows.
- Reused unchanged in this slice: canonical domain models, placeholder visibility semantics, deterministic populated fixture, and the accepted read-only SIweb configuration, concurrency gate, connector, parser, and snapshot loader.
- New platform code: a thin launcher, one Windows UI/state/mapper boundary, separate Canvas/SIweb Windows Credential Manager services, an SIweb session validator and snapshot merger, atomic JSON snapshot storage, localized copy, a safe foreground reminder engine, focused Windows tests, and one Windows CI workflow.
- Reused Canvas code: configuration, DTOs, concurrency gate, API connector, and snapshot loader remain read-only and feed the shared domain model.
- Still deferred: automated SIweb login, the complete shared SQLite store, DeepSeek, native/background notification behavior, physical-machine accessibility verification, and a signed installer.

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

The privacy-safe friend-feedback route was added in `5e4c4ba` and its branch-independent prefilled GitHub issue link was corrected in `709cc90`. Live browser verification confirmed that the link opens GitHub's new-issue page with the bilingual title, privacy warning, release/checksum/system/reproduction fields, and sensitive-data checkboxes already populated; no issue was submitted during verification.

Windows Server 2022 run [34799244166](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34799244166) also completed successfully for feedback-form commit `5e4c4badf5ab2ea422b7e4281407e8c3cf1031a2` in 51 minutes 27 seconds. Release compilation, Windows tests, packaging-tool resolution/build, portable bundling, and artifact upload passed. The uploaded artifact is `CampusDashboard-Windows-0.1.0`, artifact id `10330934192`, size `114503097` bytes, with GitHub Actions wrapper digest `sha256:816e8d5f53d21ec594c84f63763d49b066f1baee5034a5751c426b290b837540`. A non-blocking build-cache save warning and GitHub's Node.js action deprecation notice were emitted. Three immediate local download attempts failed at GitHub's `productionresultssa6.blob.core.windows.net` endpoint, so this redundant run's wrapper and inner ZIP were not locally re-inspected; the separately selected Preview 2 artifact remains the checksum- and archive-verified release candidate described above.

## Preview 3 SIweb candidate — 2026-09-14

The reuse-first SIweb slice compiles the accepted read-only SIweb configuration, gate, connector, HTML parser, and snapshot loader into the Windows target. Windows-specific code is limited to validation of the manually supplied authorized session-cookie value, secure Credential Manager persistence, UI/state integration, and merging normalized source snapshots. The browser performs normal login; the app does not automate login or bypass SSO, CAPTCHA, MFA, or access controls. Canvas and SIweb forget actions were regression-tested to preserve the other source.

Changed candidate files include the Windows package manifest/source lists, Windows state/UI/localization and credential boundaries, source-isolated snapshot persistence, focused Windows tests, SIweb parser portability shim, CI cache behavior, README, and Windows testing guide. Five unrelated pre-existing user modifications in the macOS sync/SIweb source and tests remained unstaged and were not overwritten.

Local verification passed: Big-5's Foundation raw value matched the prior CoreFoundation conversion (`0x80000A03`), the SIweb parser passed a Windows-target syntax parse, `./scripts/test.sh` passed 244 tests in 20 suites, and `git diff --check` passed.

Windows Server 2022 run [34806098324](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34806098324) passed dependency resolution, Release build, native Windows tests, packaging-tool resolution/build, build-cache save, portable bundle creation, and artifact upload for exact functional source commit `d43707a76c9125587e428004deb2e3110b7b99b0`. The artifact is `CampusDashboard-Windows-0.1.0`, id `10334710441`, size `119328848` bytes, with Actions wrapper digest `sha256:61efd4dcd3b601df6acdbb6d9a748829f8ae7c9fcb27fd1ff09cf6e4dd4ae41f`.

The downloaded wrapper digest matched GitHub, both wrapper and inner archives passed integrity checks, and the inner checksum passed after interpreting its Windows CRLF line ending. The portable ZIP contains 20 files, including `CampusDashboard.exe` and `WindowsAppRuntimeInstaller.exe`; its SHA-256 is `d18b32e760a19acd4d81e0d07abfd884c3a15736a5e90b0db637c94ac99b2c7d`. A case-insensitive filename scan found no iCloud, EventKit, Outlook, Microsoft Graph, CalDAV, or Google Calendar integration artifact. No live Canvas, SIweb, DeepSeek, Calendar, or notification operation was performed by CI or local archive inspection.

GitHub release draft id `388185642` is named `Campus Dashboard Windows Preview 3`, reserves tag `v0.1.0-windows-preview.3`, targets documentation/feedback commit `03da86a27b2697774eb6f91af7467189bc8477f5`, and remains `draft: true`, `prerelease: true`, with no publication timestamp. Its release notes pin the binary provenance to functional commit `d43707a76c9125587e428004deb2e3110b7b99b0` and run `34806098324`. Its uploaded assets are:

- `CampusDashboard-Windows-0.1.0-portable-x64.zip`: asset id `562764492`, `119767108` bytes, GitHub release-asset digest `sha256:d18b32e760a19acd4d81e0d07abfd884c3a15736a5e90b0db637c94ac99b2c7d`;
- `SHA256SUMS.txt`: asset id `562757670`, `114` bytes, GitHub release-asset digest `sha256:cbaeddd8a0a85b61400d9f3d8971befc25ac13116868480f3088268a8e63bd75`.

The draft body documents Canvas and SIweb read-only behavior, normal-browser SIweb authorization, separate Credential Manager entries, source-isolated forget behavior, bilingual six-surface UI, foreground reminders, installation/testing steps, exact provenance, and the absence of iCloud or substitute external calendars. Documentation commit `d014621` adds `docs/windows-preview-3-friend-guide.zh-CN.md`, a concise Simplified Chinese download, checksum, launch, source-sync, isolation, privacy, and defect-report walkthrough. Commit `9ce1bf6` updates the bilingual privacy-safe issue form from Preview 2 to Preview 3 and adds SIweb/source-isolation failure choices; commit `03da86a` adds a clickable pre-filled feedback entry to the friend guide and release notes. The verified draft body and target were updated without changing the two binary assets, release id, or draft/prerelease state. A live unauthenticated check confirmed that the repository is public and that both the Chinese guide and pre-filled feedback entry return HTTP 200. Docs-triggered Windows run [34815063084](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34815063084) completed setup, dependency resolution, and Release compilation, then was intentionally cancelled during redundant Windows tests because no product source changed and run `34806098324` remains the selected fully passed binary evidence. Publishing remains an external public action and requires fresh immediate user confirmation.

## Remaining acceptance work

1. After fresh immediate user confirmation, publish the already verified Preview 3 draft without changing its tested assets or stated limitations.
2. Pass the user's real Windows-machine launch, Canvas and SIweb sources, restart, credentials, independent forget-source behavior, navigation, scaling, keyboard, localization, foreground-reminder, offline, clear-data, and privacy smoke using Preview 3 after publication.
3. Reuse compatible AI, complete persistence, native/background reminders, and presentation/accessibility behavior behind explicit platform boundaries before daily-use acceptance.

Stage 16W cannot be marked `PASS` until the Windows CI artifact and real Windows acceptance matrix pass.
