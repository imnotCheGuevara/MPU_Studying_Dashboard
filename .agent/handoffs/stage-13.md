# Stage 13 handoff

Status: PARTIAL

Assessment date: 2026-09-07 (Asia/Macau)

## Decision and remaining gate

The tenant-specific Microsoft Entra authorization boundary, Keychain token cache, metadata-only Microsoft Graph probe, Settings states, localization, tests, and dated assessment are implemented. The code stays within Stage 13: it does not synchronize mail, persist mail, display a mailbox, call DeepSeek with mail, or perform any remote mailbox mutation.

The real school-account acceptance item is not complete. No user-supplied Application (client) ID or Directory (tenant) ID is configured, so the signed app has not contacted the school tenant. The signed aggregate-only command fails closed as `BLOCKED category=configuration_missing`, and Canvas/SIweb remain independent. School consent, administrator approval, MFA/Conditional Access, metadata-read success, local disconnect, and reconnect therefore remain unverified. This handoff must not be marked `PASS` and Stage 14 must not start.

If the school requires an administrator to create or approve the native app, the result is No-Go/BLOCKED until the administrator completes the normal Entra review. No password, IMAP, application-permission, embedded-login, scraping, or cross-tenant fallback is permitted.

## Effective authorization contract

- Single-tenant UUID authority only: `https://login.microsoftonline.com/{tenant UUID}/oauth2/v2.0`; `common`, `organizations`, `consumers`, arbitrary endpoints, and cross-tenant claims are rejected.
- Public native macOS authorization-code flow with PKCE S256, a fresh 64-byte verifier, 32-byte state, and 32-byte nonce. Authorization opens in the macOS system browser.
- Exact registered callback: `msauth.com.campusdashboard.desktop://auth`, also registered in the packaged `Info.plist`. Scheme, host, empty path, port, user info, fragment, duplicate parameters, state, and one-time code use are validated.
- Requested delegated scopes: `https://graph.microsoft.com/Mail.ReadBasic`, `openid`, and `offline_access` only. Returned scopes must remain inside the allowlist and include `Mail.ReadBasic`.
- Token exchange and refresh use the fixed tenant HTTPS endpoint with redirects disabled. ID-token issuer, tenant, audience, nonce, expiry, and not-before time are checked. Graph access tokens remain opaque.
- Token state is stored only in macOS Keychain service `com.campusdashboard.desktop.outlook`. Disconnect removes local tokens and the pending transaction without making a mailbox request.
- The only Stage 13 Graph request is `GET https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$select=receivedDateTime&$top=1`. Its result is reduced to an aggregate zero/one count and is not persisted.
- Admin-consent denial, Conditional Access/policy block, cancellation, expiry/revocation, offline transport, Graph claims challenge, and Keychain failure fail closed. A claims challenge is transient and never logged or persisted.

## Current official Microsoft references

References were reviewed on 2026-09-07 and are summarized in `docs/outlook-connection-assessment.md`:

- [OAuth 2.0 authorization-code flow and refresh](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)
- [MSAL iOS/macOS redirect URI format](https://learn.microsoft.com/en-us/entra/msal/objc/redirect-uris-ios)
- [Mobile/native app registration](https://learn.microsoft.com/en-us/entra/identity-platform/scenario-mobile-app-configuration)
- [Microsoft Graph permissions reference: Mail.ReadBasic](https://learn.microsoft.com/en-us/graph/permissions-reference#mailreadbasic)
- [User and administrator consent overview](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/user-admin-consent-overview), [configure user consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent), and [admin consent workflow](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/admin-consent-workflow-overview)
- [Claims challenges](https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge)
- [Access-token lifetime](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens#token-lifetime) and [configurable token lifetimes](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes)
- [List messages](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0) and [message delta](https://learn.microsoft.com/en-us/graph/api/message-delta?view=graph-rest-1.0)
- [Graph best practices](https://learn.microsoft.com/en-us/graph/best-practices-concept#handling-expected-errors), [errors](https://learn.microsoft.com/en-us/graph/errors), and [throttling limits](https://learn.microsoft.com/en-us/graph/throttling-limits)

## Changed files

- Added `Sources/CampusDashboard/Connectors/Outlook/OutlookAuthModels.swift`.
- Added `Sources/CampusDashboard/Connectors/Outlook/OutlookAuthorizationService.swift`.
- Added `Sources/CampusDashboard/Connectors/Outlook/OutlookGraphMetadataProbe.swift`.
- Added `Sources/CampusDashboard/Connectors/Outlook/OutlookLocalTool.swift`.
- Updated `Sources/CampusDashboard/App/AppEnvironment.swift`.
- Updated `Sources/CampusDashboard/App/CampusDashboardApp.swift`.
- Updated `Sources/CampusDashboard/App/DashboardModel.swift`.
- Updated `Sources/CampusDashboard/App/Localization.swift`.
- Updated `Sources/CampusDashboard/Features/Settings/SettingsView.swift`.
- Updated `Resources/Info.plist`.
- Added `Tests/CampusDashboardTests/OutlookAuthorizationTests.swift`.
- Added `docs/outlook-connection-assessment.md`.
- Added this handoff.

No main-thread-owned roadmap, status, constraints, execution-rule, stage-prompt, project-specification, or `AGENTS.md` file was edited.

## Automated and build evidence

| Check | Result |
| --- | --- |
| `./scripts/test.sh` | PASS before the continuation workspace restoration: 209 tests in 18 suites, 0 failures; exit 0. Complete log: `/tmp/campus-stage13.n2F2tx/full-tests.log`. Per the main conversation's instruction, this complete suite was not repeated. |
| `./scripts/test.sh --filter OutlookAuthorizationTests` | PASS after restoration: 12 declared protocol/UI/isolation tests in 1 suite, including parameterized rejection of 5 forbidden scopes and all 6 status values; 0 failures. Log: `/tmp/campus-stage13-restored-focused.log`. |
| `swift package clean && swift build --configuration release --jobs 1` | PASS after restoration; clean Release build completed in 46.67 seconds. Log: `/tmp/campus-stage13.n2F2tx/restored-clean-release.log`. |
| `./scripts/build-app.sh` | PASS after restoration; signed `dist/Campus Dashboard.app` produced. Log: `/tmp/campus-stage13.n2F2tx/restored-build-app.log`. |
| `./scripts/verify-app.sh` | PASS after restoration; Launch Services launch and packaged Keychain create/read/delete smoke passed. Log: `/tmp/campus-stage13.n2F2tx/restored-verify-app.log`. |
| `codesign --verify --deep --strict "dist/Campus Dashboard.app"` | PASS. |
| Packaged plist callback scan | PASS; the signed app contains only the expected `msauth.com.campusdashboard.desktop` callback scheme. |
| Signed entitlement scan | PASS; app sandbox and outbound network client are present, and inbound network server is absent. Existing Calendar entitlement remains present. |
| Stage 13 security/privacy scans | PASS; no write/send/shared/application mail scope, client secret, password/ROPC/IMAP flow, injectable/custom transport, Outlook-to-AI path, or Outlook token/Graph material in persistence/privacy modules was found. `git diff --check` also passed. |
| `swiftformat --lint Sources Tests` | NOT RUN; the optional external `swiftformat` executable is not installed. Repository-required builds/tests and whitespace checks passed; no environment change was made. |

The protocol suite covers UUID-only configuration; minimum scopes; PKCE/state/nonce entropy; system-browser request construction; exact callback and duplicate/state rejection; authorization-code one-time use; Keychain save/delete/failure; ID-token issuer/tenant/audience/nonce/time validation; excess-scope rejection; refresh and refresh-token rotation; expiry/revocation; cancellation; offline behavior; admin approval and policy block; MFA/Conditional Access claims challenge passthrough; the exact bounded metadata-only Graph request; all six display states; and Canvas/SIweb isolation when Outlook is unavailable.

## Signed-app and UI evidence

- The signed aggregate-only command `--outlook-metadata-smoke <sandbox result path>` returned `BLOCKED category=configuration_missing` without starting authorization or a Graph request. Its output contains no identity, address, subject, message ID, body, token, header, tenant, client ID, or raw response.
- The signed deterministic `--stage13-ui-qa` preview was inspected through the macOS accessibility tree. It uses synthetic registration values, disables production dependencies/background work, and performs no network operation.
- English states verified: `disconnected`, `authorizing`, `connected`, `expired`, `adminApprovalRequired`, and `policyBlocked`. Connected alone enables the metadata-only check; blocked/expired/disconnected states keep it disabled. Disconnect is available when local token state may need clearing.
- Simplified Chinese disconnected UI was verified, including `学校 Outlook 邮箱`, `委托式只读授权`, local client/tenant fields, exact redirect guidance, system-browser connection action, disabled metadata action, minimum-scope explanation, and explicit administrator/Conditional Access hard gates.
- The localization test iterates all six status values, so each English state has a Simplified Chinese mapping.

## Required local user/administrator actions

1. In the school's permitted Microsoft Entra administration process, create or approve a **single-tenant public native iOS/macOS app** for only that school directory.
2. Use bundle ID `com.campusdashboard.desktop` and register exactly `msauth.com.campusdashboard.desktop://auth` as the redirect URI.
3. Add only delegated Microsoft Graph `Mail.ReadBasic`. Do not add application permissions, `Mail.Read`, `Mail.ReadWrite`, `Mail.Send`, shared-mailbox permissions, or a client secret. The app itself requests `openid` and `offline_access` for validated sign-in and refresh.
4. Enter the Application (client) ID and Directory (tenant) ID locally in Campus Dashboard Settings. Do not place tokens, credentials, tenant details, or school-account information in chat, logs, screenshots, command arguments, or this handoff.
5. If user consent is disabled, use the school's normal administrator approval workflow. A denial or policy block is a hard No-Go; do not bypass it.
6. Rebuild/launch the signed app if registration metadata changed, complete system-browser sign-in and any Microsoft-hosted MFA/Conditional Access, run the metadata-only check once, disconnect and verify local token removal, then reconnect. Record only fixed status categories and aggregate zero/one results.

Until step 6 succeeds with the actual school account—or a privacy-safe administrator/policy block is recorded—Stage 13 remains `PARTIAL` and does not authorize Stage 14.
