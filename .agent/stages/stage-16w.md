# Stage 16W — Windows application port

Status: `IN PROGRESS`

## Goal

Deliver a Windows build of Campus Dashboard that reuses the accepted Swift domain, source, normalization, persistence, and safety rules wherever they compile cleanly. Replace Apple-only UI and operating-system services with Windows-native boundaries. The Windows product deliberately omits iCloud and all external-calendar writes; Today and Schedule remain in-app views.

## Required startup context

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the most recent Stage 16W handoff when resuming. Read Stage 15T material only for a named regression or model/UI gap. Stage 15S remains an independent macOS real-calendar acceptance gate and must not be treated as a Windows prerequisite.

The main conversation owns this cross-platform stage and may update central control files. Preserve the accepted macOS product and its current tests while adding the Windows distribution.

## Reuse-first implementation scope

- Keep one repository and one canonical Swift domain model. Reuse deterministic fixtures and compatible parsing, normalization, persistence, sync, AI validation, presentation, and localization code rather than translating business rules into a second language.
- Prove the toolchain and UI choice with the smallest useful Windows slice in GitHub Actions before migrating additional services. Prefer SwiftCrossUI's native WinUI backend while it remains buildable and distributable; do not add a custom abstraction layer merely to hide it.
- Keep Apple-only implementations behind macOS build boundaries: SwiftUI/AppKit, EventKit, Security/Keychain, UserNotifications, ServiceManagement, WebKit, Network framework, and Darwin-only code.
- Add only the Windows replacements needed by the product: WinUI presentation, Windows Credential Manager or DPAPI-backed credential protection, local notifications or an explicit in-app fallback, browser-based authorized login where required, local launch/background controls, and a distributable package.
- Remove the Calendar settings/integration surface from the Windows product. Do not add Outlook, Microsoft Graph, mailbox access, Google Calendar, CalDAV, or another calendar substitute.
- Preserve Canvas and SIweb as read-only. Preserve explicit confirmation for all inferred dates before they become eligible for deadline reminders or confirmed in-app schedule changes.

## Delivery slices

1. Windows CI compiles a native window from the existing domain model and synthetic fixtures without affecting the macOS package.
2. The Windows app reads the same local normalized data shape and exposes Today, Schedule, Tasks, Announcements, Needs Review, and Settings without external-calendar controls.
3. Canvas, SIweb, DeepSeek consent, credential protection, persistence, sync, and reminder behavior work through Windows-compatible adapters with the existing safety semantics.
4. GitHub produces a versioned installable or portable Windows artifact with setup, upgrade, uninstall, data-location, privacy, and diagnostic instructions.
5. The user completes a real Windows smoke test; defects return to this stage until the Windows acceptance matrix passes.

## Prohibited changes

- No Canvas/SIweb writes, login bypass, CAPTCHA/MFA bypass, new mailbox path, Outlook/Graph access, or external training/upload of user corrections.
- No iCloud, EventKit, Apple Calendar, or other external-calendar integration in the Windows target.
- No secret in source, Git, SQLite, fixtures, logs, screenshots, commands, build artifacts, or handoffs.
- No weakening of macOS Stage 15S calendar targeting, action-time approval, or dedicated-calendar isolation.
- Do not claim Windows completion from a macOS-only build or synthetic screenshot. A Windows runner build and a real Windows smoke are mandatory.

## Required verification

- macOS regression suite/build remains green after manifest and source-boundary changes.
- Windows GitHub Actions resolves dependencies and builds the production executable from a clean checkout.
- Tests cover every newly introduced cross-platform rule and Windows adapter with security or side-effect risk.
- The Windows artifact launches on the user's test machine, stores secrets only in the Windows credential facility, reads sources without writes, survives restart, and shows the complete learner workflow.
- Windows UI has complete English and Simplified Chinese system localization, keyboard navigation, accessible labels, sensible scaling, and clear empty/error/offline states.
- Repository and artifact scans find no credentials or prohibited Outlook/iCloud integration in the Windows target.

## Acceptance and handoff

Maintain `.agent/handoffs/stage-16w.md` with changed files, reuse decisions, exact commands and results, CI run links/identifiers, package hash, Windows smoke evidence, limitations, and privacy-safe diagnostics. Mark it `PASS`, `PARTIAL`, or `BLOCKED`. `PASS` requires both automated Windows delivery and the user's real-machine acceptance; until then Stage 16W stays active.
