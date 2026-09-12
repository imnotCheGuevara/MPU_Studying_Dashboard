# Campus Dashboard

## 中文介绍

Campus Dashboard 是一款面向澳门理工大学（Macao Polytechnic University，MPU）学生的本地化 macOS 学习信息仪表板。**本项目基于澳门理工大学现行使用的 Canvas 教学平台与 SIweb 教务及课表信息系统开发**，希望把分散在不同系统中的课程、作业、公告和课表信息整理到一个清晰、统一的桌面应用中。

macOS 版以只读方式连接用户授权的 Canvas 与 MPU SIweb，学校信息系统中的原始数据始终是权威来源，应用不会向 Canvas 或 SIweb 提交或修改任何资料。它提供今日概览、课表、任务、公告、待确认事项、专用 Apple 日历同步、本地提醒，以及须经用户确认后才能生效的 AI 辅助信息整理。

隐私方面，账户凭据与会话信息仅保存在 macOS 钥匙串中，学习数据主要保存在本机；外部 AI 默认不会启用或接收数据。本项目为独立开发的学生工具，并非澳门理工大学官方产品，也不代表学校认可或背书。

## English overview

Campus Dashboard is a local-only macOS learning dashboard. It includes read-only Canvas and MPU SIweb connectors, deterministic synchronization, a dedicated-calendar EventKit boundary, local notifications, user-controlled background scheduling, and a controlled AI confirmation queue. External AI is not configured or contacted.

## Requirements

- macOS 14 Sonoma or later (the package's documented minimum)
- Swift 6.0 or later, supplied by Xcode or Apple Command Line Tools

The Swift package builds the native SwiftUI executable. `scripts/build-app.sh` deterministically promotes it into a signed macOS application bundle with the stable identifier `com.campusdashboard.desktop`.

## Build, test, and run

From the repository root:

```sh
swift package clean
swift build --jobs 1
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh
open "dist/Campus Dashboard.app"
```

`scripts/test.sh` runs `swift test` directly when the installed toolchain exposes Swift Testing normally. It also supplies the standard Command Line Tools framework paths on installations where SwiftPM does not discover them automatically.

The packaging script creates `dist/Campus Dashboard.app`, installs the checked-in `Info.plist`, and applies an ad-hoc signature with the checked-in sandbox entitlement baseline. The verification script checks identity/signature, launches the bundle through Launch Services, and uses the packaged application identity to perform a generated-value Keychain create/read/delete smoke test. Its result contains no secret.

The ad-hoc signature is a reproducible local-development baseline, not a release identity. When the project adopts full Xcode, select a stable Apple Development/Developer ID team, preserve the Bundle ID, enable App Sandbox, and provision only reviewed capabilities. EventKit usage descriptions, notification/background configuration, hardened runtime, and notarization belong to their later implementation stages.

## Explore the Stage 01 UI

Use the sidebar to open all six primary pages:

- Today
- Schedule
- Tasks
- Announcements
- AI Confirmation Queue
- Settings

The signed production app loads Today, Schedule, Tasks, and Announcements from the unified SQLite store. **Refresh** runs the configured Canvas and SIweb synchronization pipeline and reloads the committed database snapshot. Synthetic preview scenarios are available only to tests and explicitly constructed development previews; production does not expose the **Preview state** menu or synthetic footer.

Settings includes an **English / 简体中文** language selector. It immediately localizes navigation, page headings, important states, and primary controls; synchronized source content remains unchanged.

The Tasks and Announcements pages preserve completion/read state locally against stable synchronized object IDs and never write it back to a school source. The confirmation queue shows provenance, confidence, rationale, conflicts, related-item suggestions, inferred dates, and an auditable confirm/correct/reject/undo workflow. AI assistance defaults off; unconfirmed inferred dates remain in the local confirmation boundary and cannot reach Calendar or deadline notifications.

## Canvas connector and secure local setup

The connector supports current-student courses, assignment dates as effective for the requesting user, Classic Quiz/New Quiz/external-tool classification when Canvas exposes the relevant fields, and course announcements. It follows same-origin Canvas `Link` pagination, uses an explicit cancellation-safe concurrency gate, records rate-limit headers, applies capped exponential retry with jitter, and emits only redacted error categories. Every Canvas request is `GET` with no body.

Only use an access token if the institution supports and authorizes that method for this account. Build the signed app, then run its local terminal setup. The URL is ordinary local configuration; token input is hidden and stored directly in macOS Keychain:

```sh
./scripts/build-app.sh
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --canvas-configure
```

The URL prompt validates the HTTPS origin before the app asks for authorization. At the token prompt, pasted or typed characters must remain invisible. If they appear, cancel immediately and revoke that token. Do not put a Canvas token in a shell argument, source file, `.env` file, fixture, log, screenshot, or task message. After setup, run the minimal real read-only check locally:

```sh
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --canvas-smoke-test
```

The smoke result prints aggregate counts or a redacted error category only. It does not print identifiers, URLs, response bodies, or authorization. See [Canvas connector assessment](docs/canvas-connector.md) for endpoints, access assumptions, fields, retry behavior, and known limits.

## MPU SIweb read-only connector

The SIweb connector is deny-by-default: only the explicitly configured same-origin HTTPS Class Time page is eligible, every crawler request is a body-free `GET`, and the exact MPU table contract must match before any meeting is emitted. It includes stable-ID derivation, parser versioning, bounded concurrency, minimum request spacing, classified retry, login/session-expiry detection, and redacted diagnostics.

Authorization is performed in the signed app's non-persistent web view. Sign in personally on MPU's page; the application does not read the login form and stores only the target SIweb session in macOS Keychain. Session material must never be pasted into chat, a shell argument, source, a fixture, a log, or a screenshot. The smoke mode prints aggregate counts only:

```sh
./scripts/build-app.sh
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-authenticate
"dist/Campus Dashboard.app/Contents/MacOS/CampusDashboard" --siweb-smoke-test
```

See [SIweb connector assessment](docs/siweb-connector.md) for the exact safety boundary, MPU parser contract, limitations, and acceptance evidence.

## Current architecture

```text
Sources/CampusDashboard/
├── App/             app entry point, navigation, and in-memory view model
├── Domain/          source-independent UI-facing domain types
├── Persistence/     SQLite connection, migrations, records, and repositories
├── Security/        Keychain-backed and fake secret stores
├── Services/        external-system protocols and deterministic fakes
├── Connectors/      read-only Canvas/SIweb adapters and snapshot boundaries
├── AI/              minimal-input parsing, strict validation, persistence, evaluation, and confirmation
├── Calendar/        dedicated-calendar ownership and EventKit integration
├── Notifications/   local notification policy and idempotent scheduling
├── Background/      visible hourly-target and recovery scheduling
├── Fixtures/        fixed, completely synthetic sample dataset
└── Features/        one folder per primary page plus shared UI components
Tests/
└── CampusDashboardTests/  fixture, state, and view-model behavior tests
```

Production UI reads only committed synchronized records from the app's Application Support SQLite store; it never falls back to fixtures when the database is empty or a source fails. Official source fields, local state, and suggested/inferred fields use separate tables/columns. AI consumes only committed Canvas records, runs after deterministic normalization, and has no connector, EventKit, or UserNotifications capability.

## Privacy controls and diagnostics

Settings shows independent health for Canvas, SIweb, Calendar, Notifications, AI, and background scheduling. Failures use fixed categories with a recovery action; one unavailable subsystem does not disable unrelated local views or the other source.

Local data can be cleared by category: source cache, local completion/read state, sync history, AI history, or completed notification history. These actions never clear Keychain credentials or delete Apple Calendar events. Credential removal has its own confirmation and removes only the Canvas token and authorized SIweb session from macOS Keychain. Apple Calendar cleanup is also separate: the app first previews only events whose active binding, dedicated-calendar identity, source identity, and ownership marker can all be revalidated, then revalidates again before deletion.

The diagnostic viewer/export uses an allowlist rather than redacting arbitrary payloads after collection. It contains only schema/format versions, timestamps, source and subsystem status categories, fixed recovery guidance, and aggregate table counts. It excludes source URLs, account/object/event identifiers, titles, descriptions, raw records, error bodies, credentials, cookies, authorization headers, and Keychain data.

Keyboard basics include standard sidebar navigation, Command-R to refresh, Command-comma to open Settings, and Shift-Command-D to refresh the diagnostic preview. Destructive controls have explicit labels and confirmation dialogs.

## Product documentation

- [Current lightweight context](.agent/CURRENT.md)
- [Per-stage contracts](.agent/STAGE_PROMPTS.md)
- [Project specification](docs/project-spec.md)
- [Stage roadmap](.agent/ROADMAP.md)
- [Global constraints](.agent/PROJECT_CONSTRAINTS.md)
- [Persistence architecture](docs/architecture.md)
- [Versioned data model](docs/data-model.md)
- [Canvas connector assessment](docs/canvas-connector.md)
- [SIweb connector assessment](docs/siweb-connector.md)
- [Controlled AI parsing](docs/ai-assisted-parsing.md)
- [Privacy, clearing, and diagnostics](docs/privacy-security.md)
