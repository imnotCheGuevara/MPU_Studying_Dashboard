# Campus Dashboard Windows adaptation — review draft

Status: **AWAITING USER REVIEW — DO NOT CONTINUE IMPLEMENTATION**

This document proposes how to adapt the accepted macOS product to Windows. It is a design and delivery plan only. No additional Windows code, CI configuration or fixes, packaging, or publishing is authorized until the user approves this document.

## Current repository situation

- The accepted macOS baseline is commit `776b2ef` on `main`.
- Branch `codex/windows-port` already contains two draft implementation commits: `101e014` and `40f30f0`.
- Those commits are already present on the branch's GitHub remote, but they have not been accepted as the Windows design or release.
- Both slices are preserved unchanged as **unreviewed drafts**. The review-gate commit changes documentation only; no further implementation proceeds before approval.
- GitHub may automatically run the existing Windows workflow after the documentation push. Any such result is informational only and will not be acted on or counted as acceptance before review approval.

## Recommended first release

- Target: Windows 11, x64.
- Surfaces: Today, Schedule, Tasks, Announcements, Needs Review, and Settings.
- Sources: Canvas and SIweb, both read-only.
- AI: optional DeepSeek analysis under the same explicit consent, minimum-disclosure, direct-HTTPS, schema-validation, and local-correction rules as macOS.
- Schedule: internal app view only. Windows will not integrate with iCloud, EventKit, Outlook, Microsoft Graph, Google Calendar, CalDAV, or any other external calendar.
- Languages and access: complete English and Simplified Chinese UI, keyboard navigation, accessible labels, sensible display scaling, and clear empty/offline/error states.

## Reuse and replacement map

| macOS component | Windows plan | Review rule |
| --- | --- | --- |
| Canonical Swift domain, fixtures, normalization, parsers, sync and safety rules | Reuse directly wherever they compile cleanly | Do not fork business rules into a second implementation |
| SwiftUI/AppKit UI | First prove the existing SwiftCrossUI native WinUI approach on `windows-latest` | If the clean CI probe fails or blocks accessibility/distribution, stop and review a native Windows host around the shared core before changing direction |
| Keychain | Windows Credential Manager, with DPAPI-backed protection where needed | No secret in SQLite, configuration, logs, diagnostics, fixtures, commands, commits, or artifacts |
| EventKit / Apple Calendar | Omit completely | No Windows calendar substitute |
| UserNotifications | In-app reminders for the first beta; Windows App SDK notifications before daily-use release | Notification permission/failure must not block source sync or in-app views |
| ServiceManagement | Explicit opt-in startup/background behavior using supported Windows APIs; Task Scheduler only if necessary | No hidden persistence and no rapid polling loop |
| WebKit authorization view | System browser plus an approved redirect/session handoff | No scraping, credential capture, MFA/CAPTCHA bypass, or school-policy bypass |
| Application Support + SQLite | `%LOCALAPPDATA%\\Campus Dashboard` with the same versioned data model | Upgrade, backup, clear-data, and uninstall behavior must be documented and tested |

## Delivery gates

1. **Review approval** — agree on the four product decisions below. No code resumes before this gate.
2. **Clean Windows proof** — from a clean checkout, `windows-latest` builds and launches the smallest native window using the shared domain and synthetic fixtures. macOS tests remain green.
3. **Local product core** — add versioned SQLite, normalized data, internal Today/Schedule/Tasks/Announcements/Needs Review/Settings, and deterministic offline/error behavior.
4. **Read-only services and security** — add Canvas and SIweb adapters, Credential Manager/DPAPI, optional DeepSeek consent/validation, and auditable background cadence. Prove every connector is read-only and source failures remain isolated.
5. **Windows experience** — finish English/Chinese localization, keyboard and screen-reader semantics, scaling, reminders, setup/recovery, diagnostics, and privacy controls.
6. **Distribution** — publish a versioned portable ZIP first for fast testing. After the product stabilizes, produce a signed MSI or MSIX installer with upgrade and uninstall instructions.
7. **Real-machine acceptance** — the user launches the artifact on a Windows 11 x64 machine, completes authorized source setup without exposing secrets, verifies restart/persistence/offline recovery, and walks through the complete learner flow. Defects return to Stage 16W until the matrix passes.

## Acceptance matrix

| Area | Required evidence |
| --- | --- |
| Clean build | GitHub `windows-latest` build and tests pass from a clean checkout; artifact hash recorded |
| macOS regression | Existing macOS test/build/signature gates remain green after shared-code changes |
| UI completeness | All six surfaces work in English and Simplified Chinese at common Windows scaling levels |
| Accessibility | Keyboard-only navigation, focus order, visible focus, accessible names, and screen-reader smoke pass |
| Persistence | Data survives restart; schema upgrade and clear-data behavior pass |
| Credentials | Secrets are stored only through Windows Credential Manager/DPAPI and are absent from repository and artifact scans |
| Sources | Canvas and SIweb read successfully without school-system writes; expiry, offline, structural change, and independent failure states are recoverable |
| AI | Opt-in consent, minimum disclosure, strict schema validation, budget limits, and local-only corrections pass |
| Scheduling | Internal Schedule and confirmed changes work; no external-calendar code or dependency is present |
| Background/reminders | User-controlled cadence avoids rapid loops and duplicate reminders; disabled/denied states fail safely |
| Packaging | Portable ZIP instructions pass first; signed installer upgrade/uninstall passes before broad distribution |
| Real Windows smoke | User verifies launch, setup, sync, restart, recovery, localization, and daily learner workflow on physical Windows hardware |

## Main risks and controls

- **Swift/WinUI dependency risk:** prove the UI toolchain before migrating services; stop for review if native accessibility or packaging is not viable.
- **Apple-framework coupling:** move only narrow protocol boundaries and preserve one canonical domain implementation; macOS regression gates run after every shared-code slice.
- **Credential/session portability:** implement Windows-native secure storage and browser handoff before any real account setup; never migrate Keychain material automatically.
- **Background execution differences:** start with explicit foreground/manual sync plus safe in-app reminders, then add only documented opt-in Windows background behavior.
- **Installer trust:** use portable ZIP for the first controlled smoke; require code signing before a broadly distributed installer.
- **Private-data leakage:** keep CI synthetic, retain aggregate-only diagnostics, scan repository/artifacts, and perform real setup only on the user's Windows machine.

## Decisions for review

Recommended defaults are:

1. Minimum system: **Windows 11 x64**.
2. Distribution: **portable ZIP for the first controlled test, then a signed MSI/MSIX installer**.
3. Reminders: **in-app reminders in the first beta; native Windows notifications required before daily-use release**.
4. Migration: **no automatic macOS data or credential transfer in the first Windows release**.

To approve all recommended defaults, reply:

> 批准 Windows 方案，按推荐默认项执行

Or list the numbered items you want changed. Until approval, Stage 16W remains paused and the preserved draft code will not be advanced or published.
