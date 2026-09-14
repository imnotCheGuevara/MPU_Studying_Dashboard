# Campus Dashboard Windows Preview 3

Controlled, unsigned Windows 11 x64 preview for real-machine testing.

## Included

- Native WinUI application with Today, Schedule, Tasks, Announcements, Needs Review, and Settings.
- English and Simplified Chinese UI with a persistent language choice.
- Authorized read-only Canvas synchronization.
- Advanced read-only SIweb timetable beta that reuses the accepted connector and parser. Sign in normally in the system browser and provide only the authorized request Cookie value through the app's secure field.
- Separate Canvas and SIweb credentials in Windows Credential Manager.
- Restart-safe normalized offline snapshots in `%LOCALAPPDATA%\CampusDashboard\snapshot-v1.json`.
- Independent **Forget Canvas** and **Forget SIweb** actions that preserve the other source's data.
- Foreground-only in-app reminders. Official dates take precedence and suggested dates require explicit confirmation.

## Privacy and product boundaries

- No iCloud, Apple Calendar, EventKit, Outlook, Microsoft Graph, Google Calendar, CalDAV, or other external-calendar integration.
- No write access to Canvas or SIweb.
- No automated SIweb login and no bypass of SSO, CAPTCHA, MFA, access controls, tenant policy, or school rules.
- Never include access tokens, cookies, school content, account URLs, raw API responses, snapshots, Credential Manager contents, or private screenshots in defect reports.

## Known limitations

- Unsigned portable ZIP intended for controlled testing.
- DeepSeek, background refresh, native Windows notifications, automated SIweb login, and a signed installer are not included yet.
- A physical Windows-machine smoke test is still required; successful Windows CI is not daily-use acceptance.

Download both assets and verify the ZIP against `SHA256SUMS.txt` before extracting it. If Windows App Runtime is missing, run the bundled `WindowsAppRuntimeInstaller.exe` once. A concise Chinese walkthrough is available in [the Preview 3 friend testing guide](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/blob/codex/windows-port/docs/windows-preview-3-friend-guide.zh-CN.md); full setup, SIweb session, upgrade, uninstall, privacy, and smoke-test instructions are in [the Windows preview testing guide](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/blob/codex/windows-port/docs/windows-preview-testing.md).

For a privacy-safe defect report, use the [pre-filled bilingual feedback entry](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/blob/codex/windows-port/docs/windows-preview-testing.md#privacy-safe-defect-report) and remove all private school or account data before submitting.

Provenance: the attached artifact was built and tested on Windows Server 2022 by [workflow run 34806098324](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/actions/runs/34806098324) from exact functional source commit `d43707a76c9125587e428004deb2e3110b7b99b0`. The selected Actions artifact id is `10334710441`, its wrapper SHA-256 is `61efd4dcd3b601df6acdbb6d9a748829f8ae7c9fcb27fd1ff09cf6e4dd4ae41f`, and the attached portable ZIP SHA-256 is `d18b32e760a19acd4d81e0d07abfd884c3a15736a5e90b0db637c94ac99b2c7d`.
