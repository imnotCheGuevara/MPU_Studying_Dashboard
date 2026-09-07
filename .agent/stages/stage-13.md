# Stage 13 — Outlook tenant feasibility and delegated authorization

## Startup context and allowed reads

Read only `AGENTS.md`, `.agent/CURRENT.md`, this file, and the latest directly related handoff below. If this stage is being resumed from `PARTIAL` or `PAUSED`, its own handoff takes precedence. Use targeted `rg -n` and a narrow `sed -n` range for any additional reference; do not read the full historical prompt index, full specification, or all handoffs.

Latest directly related handoff: .agent/handoffs/stage-13.md when resuming the current PARTIAL stage; otherwise .agent/handoffs/stage-10r.md.

## Prerequisite gate

Stage 13 is explicitly paused outside the active release path. Stop without implementation unless a future main-thread decision records school-policy clearance and sets Stage 13 to READY or IN PROGRESS in `.agent/CURRENT.md`.

## Stage contract

You own Stage 13 only: Microsoft Entra/Graph feasibility and secure delegated authorization for the user's school Outlook account. Do not build general mail synchronization or mailbox UI in this stage.

First create a dated connection assessment from current official Microsoft documentation and the actual school tenant behavior: tenant/authority choice, public native app registration, registered redirect URI, system-browser authorization-code flow with PKCE S256/state, delegated permission/consent policy, token lifetime/refresh/revocation, Conditional Access/MFA, Graph mail endpoints, pagination/delta capability, throttling, failure modes, and school policy. Use a user-supplied local client ID/tenant configuration; a client ID is not a secret, but never invent one. Do not embed a client secret.

Implement the authorization boundary and Settings status using the system browser. Begin with delegated `Mail.ReadBasic` for metadata-only capability validation, plus only identity scopes actually required by the chosen library/flow. Tokens belong only in Keychain. Sign-out/revoke must clear local tokens without changing the mailbox. Reject unexpected redirect/state/issuer/tenant, excessive scopes, application permissions, `Mail.ReadWrite`, `Mail.Send`, ROPC/password capture, IMAP credentials, embedded login scraping, and Outlook web scraping.

Allowed scope: a new Outlook/Microsoft Graph connector-auth module, Keychain token cache, source-account capability/status fields and additive migrations, Settings/Localization UI, fake transports/tests, connection assessment documentation, and .agent/handoffs/stage-13.md. Do not persist message bodies, implement delta sync, call DeepSeek on mail, modify remote mail, or begin Stage 14.

Acceptance:
- Protocol tests cover PKCE S256, high-entropy verifier/state, exact redirect handling, code one-time use, token refresh/expiry, cancellation, MFA/Conditional Access passthrough, tenant mismatch, consent denied/admin required, revoked token, offline behavior, and Keychain failure.
- Scope tests fail closed if returned/requested permissions exceed the allowlist; repository scans find no client secret, password flow, write/send scope, token, authorization header, or sensitive tenant output.
- Settings clearly shows disconnected/authorizing/connected/expired/admin-approval-required/policy-blocked states in English and Simplified Chinese.
- Existing Canvas/SIweb sync continues when Outlook is unavailable.
- Full suite, clean/release build, signed app, signing/plist/security scans pass.
- A real signed-app school-account smoke completes system-browser sign-in and a minimum metadata-only Graph read without recording identities, addresses, subjects, IDs, bodies, or tokens. If the tenant requires admin approval or blocks the app, document the exact privacy-safe gate and mark BLOCKED/No-Go; do not bypass it.

Write .agent/handoffs/stage-13.md with PASS, PARTIAL, or BLOCKED, dated official references, the effective delegated scopes, privacy-safe real-tenant result, and exact checks. Do not begin Stage 14.
