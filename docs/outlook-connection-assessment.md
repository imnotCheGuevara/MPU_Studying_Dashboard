# School Outlook connection assessment

Assessment date: **2026-09-07 (Asia/Macau)**
Stage: **13 — tenant feasibility and delegated authorization only**
Current decision: **PARTIAL / tenant validation pending local app registration values**

## Decision summary

The implementation is technically suitable for one school Microsoft Entra workforce tenant, but tenant admission is not yet Go. No locally supplied Application (client) ID or Directory (tenant) ID is configured, so the actual school tenant has not been contacted. Outlook stays disconnected and Canvas/SIweb continue independently.

The remaining prerequisite is a public native iOS/macOS app registration owned or approved for the school tenant. It must support only accounts in that organizational directory, use bundle ID `com.campusdashboard.desktop`, and register exactly `msauth.com.campusdashboard.desktop://auth`. The app accepts only UUID client/tenant IDs and never accepts a client secret.

## Authorization boundary

| Decision | Contract |
| --- | --- |
| Authority | Fixed tenant-specific v2 endpoints below `https://login.microsoftonline.com/{tenant UUID}/oauth2/v2.0`; `common`, `organizations`, `consumers`, arbitrary hosts, and cross-tenant claims are rejected. |
| Client/flow | Public native macOS client; authorization code + PKCE S256; no secret, certificate assertion, backend, device-code or password flow. |
| Browser/redirect | macOS system browser and exact `msauth.com.campusdashboard.desktop://auth` callback registered in `Info.plist`; scheme/host/path/port/user info/fragment, duplicate parameters, and state are checked. |
| Correlation | Fresh 64-byte verifier, 32-byte state, and 32-byte nonce per attempt. The one-time transaction is memory-only and discarded after a terminal result. |
| Scopes | Delegated `Mail.ReadBasic`, `openid`, and `offline_access` only. `openid` supports nonce/audience/issuer/tenant/time checks; `offline_access` is necessary for refresh. Returned scopes must be an allowed subset containing `Mail.ReadBasic`. |
| Validation | Token exchange uses only the fixed tenant HTTPS endpoint with redirects disabled. ID-token `iss`, `tid`, `aud`, `nonce`, `exp`, and `nbf` are checked. Graph access tokens remain opaque. |
| Storage | Access/refresh tokens, expiry, allowed scopes and tenant/client binding exist only in macOS Keychain service `com.campusdashboard.desktop.outlook`; never SQLite, UserDefaults, logs, diagnostics, fixtures, screenshots, or handoffs. Client/tenant registration values are local non-secret configuration. |
| Disconnect | Deletes the complete local token cache and pending transaction, performs no mailbox request, and changes no mail. Tenant-wide session revocation is not attempted because it could affect unrelated applications and require broader privilege. |

Microsoft's current protocol documentation requires the exact registered redirect, recommends PKCE for native apps, defines authorization codes as single-use, and says public/native clients must not use a client secret. `offline_access` is required to receive a refresh token, and a rotated refresh token must replace the old cached value. Sources: [OAuth authorization-code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow), [MSAL iOS/macOS redirect URI format](https://learn.microsoft.com/en-us/entra/msal/objc/redirect-uris-ios), and [mobile app registration](https://learn.microsoft.com/en-us/entra/identity-platform/scenario-mobile-app-configuration).

Microsoft documents delegated `Mail.ReadBasic` as access to basic properties in only the signed-in user's mailbox, excluding body/body preview, attachments and extended properties; it normally does not require admin consent. Application `Mail.ReadBasic.All`, shared-mailbox permissions, `Mail.Read`, `Mail.ReadWrite`, and `Mail.Send` are rejected. Source: [Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference#mailreadbasic).

## Tenant consent, MFA, Conditional Access, and school policy

A scope that normally allows user consent is not a tenant guarantee. The school can disable user consent, limit consent to verified publishers/tenant apps and selected low-impact permissions, require user assignment, or enable an administrator approval workflow. Any such gate is displayed as `admin approval required` or `policy blocked`; the app remains off and offers no password, IMAP, application-permission, embedded-login, or scraping fallback. Sources: [user/admin consent overview](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/user-admin-consent-overview), [configure user consent](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/configure-user-consent), and [admin consent workflow](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/admin-consent-workflow-overview).

MFA and Conditional Access stay entirely on Microsoft's hosted page. A Graph `401` claims challenge is kept only in memory, clears the unusable local token cache, and is passed once into the next interactive request. It is not logged or persisted. Source: [claims challenges](https://learn.microsoft.com/en-us/entra/identity-platform/claims-challenge).

Actual school behavior as of 2026-09-07: **not tested**, because the required local client and tenant IDs are absent. School policy for this personal local native app is also **not yet confirmed**. If only an administrator can create/approve the app, Stage 13 is No-Go/BLOCKED until that administrator completes the normal Entra review; no alternate route is permitted.

## Token lifecycle

- The app uses returned `expires_in`, not a hard-coded lifetime. Microsoft currently describes variable access-token lifetime, commonly 60–90 minutes by default.
- Before expiry, the app refreshes at the same fixed tenant endpoint and atomically replaces a rotated refresh token.
- Native-app refresh tokens have no guaranteed lifetime and can expire or be revoked. Current defaults describe 90-day maximum inactivity and until-revoked maximum age, subject to Conditional Access sign-in frequency and tenant policy.
- `invalid_grant`, tenant mismatch, revocation, or claims challenge moves Settings to expired/reconnect.

Sources: [access-token lifetime](https://learn.microsoft.com/en-us/entra/identity-platform/access-tokens#token-lifetime), [configurable token lifetimes](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes), and [refresh behavior](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#refresh-the-access-token).

## Metadata-only Graph feasibility

Stage 13 permits one bounded read after authorization:

`GET https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?$select=receivedDateTime&$top=1`

Only the aggregate zero/one count is retained as evidence. No name, address, subject, message ID, body, preview, attachment, URL, token, response body, remote request ID, or authorization header is recorded. It performs no write and persists no mail. Microsoft lists `Mail.ReadBasic` as least privilege, recommends `$select` and bounded `$top`, and requires later pagination to follow the full opaque `@odata.nextLink`. Source: [List messages](https://learn.microsoft.com/en-us/graph/api/user-list-messages?view=graph-rest-1.0).

Only a future accepted Stage 14 may implement per-folder `GET /me/mailFolders/{id}/messages/delta`, opaque `@odata.nextLink`/`@odata.deltaLink`, bounded windows and conservative deletion. Microsoft lists delegated `Mail.ReadBasic` as least privilege for this delta API. Source: [message delta](https://learn.microsoft.com/en-us/graph/api/message-delta?view=graph-rest-1.0).

## Throttling and failure behavior

Wrong redirect/state/nonce/issuer/tenant/audience, duplicate callback parameters, reused code, or excess scope caches nothing. Cancellation discards the transaction. `401`/revocation requires reconnect; `403` is a permission/policy gate; `429` must honor `Retry-After`; `5xx`, timeout and offline fail safely without blocking Canvas/SIweb. Redirects from token or Graph endpoints are not followed. Microsoft says Graph clients must handle `429`, use `Retry-After`, and back off for service-unavailable responses. Sources: [Graph best practices](https://learn.microsoft.com/en-us/graph/best-practices-concept#handling-expected-errors), [Graph errors](https://learn.microsoft.com/en-us/graph/errors), and [throttling limits](https://learn.microsoft.com/en-us/graph/throttling-limits).

## Go / No-Go gate

Go requires the signed app and real school account to complete the system-browser redirect, MFA/Conditional Access if required, delegated `Mail.ReadBasic` consent, aggregate-only HTTP 200 metadata probe, local Keychain token removal, and reconnect. Admin approval or policy block is No-Go/BLOCKED until the school administrator approves; no workaround is allowed.
