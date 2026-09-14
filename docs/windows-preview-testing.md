# Windows preview testing

This guide is for the controlled, unsigned Campus Dashboard Windows 11 x64 preview. It has no iCloud, Apple Calendar, Outlook, Microsoft Graph, Google Calendar, CalDAV, or other external-calendar integration. Canvas and SIweb access are read-only. Do not share access tokens, SIweb cookies, school content, screenshots containing private data, or the local data directory when reporting a defect.

## Download and verify

Download both files attached to the matching GitHub prerelease:

- `CampusDashboard-Windows-0.1.0-portable-x64.zip`
- `SHA256SUMS.txt`

In PowerShell, from the download directory, run:

```powershell
Get-FileHash .\CampusDashboard-Windows-0.1.0-portable-x64.zip -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

The two lowercase or uppercase hash values must match exactly. Stop if they do not match.

## First launch

1. Extract the entire ZIP to a new directory. Do not move only `CampusDashboard.exe`; its DLLs must remain beside it.
2. If Windows reports that Windows App Runtime is missing, run the bundled `WindowsAppRuntimeInstaller.exe` once, then launch the app again.
3. Run `CampusDashboard.exe`. This preview is unsigned, so Windows can display an unknown-publisher warning. Confirm only if the ZIP came from the project's GitHub release and its hash matched.
4. Before Canvas setup, verify that the app labels its sample content as preview data.

The app does not require Swift, Visual Studio, or other developer tools on the test computer.

## Canvas read-only setup

In Settings, enter only an authorized Canvas HTTPS base URL and a personal access token. The app stores the token in Windows Credential Manager, not in the snapshot or ordinary configuration. Synchronization performs read-only Canvas requests.

After a successful refresh:

1. Verify that Today, Tasks, and Announcements show expected data without exposing it in a defect report.
2. Close the app completely and reopen it.
3. Verify that the last successful normalized snapshot is still available and the token does not need to be entered again.
4. Use **Forget Canvas** only when testing removal. It removes the Canvas credential, saved URL, and Canvas-derived offline data owned by this Windows app; SIweb timetable data remains if SIweb is still connected.

Never paste a token into GitHub, chat, screenshots, logs, terminal commands, or a bug report.

## SIweb timetable read-only beta

This advanced beta reuses the accepted SIweb parser and read-only network boundary. The app does not automate SIweb login, bypass SSO, CAPTCHA, MFA, or access controls.

1. Select **Open SIweb in browser** in Settings and sign in normally in the system browser.
2. Open the browser Developer Tools **Network** panel, reload the timetable page, and select the `time_stud.asp` request.
3. Under **Request Headers**, copy only the value after `Cookie:`. Do not copy the `Cookie:` label, a password, an authorization header, or the full request.
4. Paste that value into the app's secure field and select **Save session and sync**.
5. Verify only aggregate behavior: Schedule gains the expected number of meetings and shows a healthy SIweb source status. Do not put course details in a defect report.

The value is validated before being stored in Windows Credential Manager and is never written to the normalized snapshot. If the session expires, sign in again in the browser and replace it. **Forget SIweb** removes only the SIweb credential and SIweb timetable data; saved Canvas data remains available.

## Data, upgrade, and uninstall

The normalized offline snapshot is stored at:

```text
%LOCALAPPDATA%\CampusDashboard\snapshot-v1.json
```

Credentials are stored separately in Windows Credential Manager. A portable upgrade is performed by extracting a newer verified ZIP into a new directory, closing the old app, and launching the new executable. Do not overwrite files while the app is running. The local snapshot and credentials remain available because they are not stored inside the extracted application directory.

Deleting the extracted application directory uninstalls the portable executable but deliberately leaves local data and credentials intact. To remove app-owned data first, use **Forget Canvas** and **Forget SIweb** in Settings. If the executable no longer starts, remove only Credential Manager entries whose target begins with `CampusDashboard:` and delete `%LOCALAPPDATA%\CampusDashboard` manually. Do not remove unrelated credentials or directories.

## Real-machine smoke matrix

Record only pass/fail and non-sensitive error categories for each item:

- Launch `CampusDashboard.exe` from the fully extracted directory on Windows 11 x64.
- Open Today, Schedule, Tasks, Announcements, Needs Review, and Settings.
- Switch between English and Simplified Chinese, restart, and verify that the selection persists.
- Verify Today shows only eligible foreground in-app reminders and clearly states that the beta has no background reminder service.
- Test keyboard traversal and activation without requiring a mouse.
- Test 100%, 125%, and 150% Windows display scaling for clipped or unreachable controls.
- Configure Canvas, run a read-only refresh, restart, and confirm that the offline snapshot and credential behavior are correct.
- Configure the SIweb beta using only the browser request's Cookie value, run a read-only refresh, restart, and confirm that the timetable snapshot and credential behavior are correct.
- Use **Forget SIweb** and verify that SIweb meetings and its credential disappear while Canvas data remains.
- Disconnect the network, reopen the app, and verify that cached content remains visible with a clear offline/error state.
- Use **Forget Canvas**, restart, and verify that the token, URL, and Canvas-derived snapshot data are no longer available while any connected SIweb timetable remains.
- Confirm that the Windows app contains no iCloud or external-calendar settings or authorization request.

Automated SIweb login, DeepSeek, background refresh, and native Windows notifications are not included in this preview and must not be reported as passing.

## Privacy-safe defect report

Open the bilingual [pre-filled Windows Preview feedback report](https://github.com/imnotCheGuevara/MPU_Studying_Dashboard/issues/new?title=Windows+Preview+feedback+%2F+Windows+%E9%A2%84%E8%A7%88%E7%89%88%E5%8F%8D%E9%A6%88&body=%3E+Privacy+%2F+%E9%9A%90%E7%A7%81%EF%BC%9ADo+not+include+tokens%2C+cookies%2C+school+content%2C+account+URLs%2C+raw+API+responses%2C+snapshot+files%2C+Credential+Manager+contents%2C+or+private+screenshots.+%E8%AF%B7%E5%8B%BF%E6%8F%90%E4%BA%A4%E4%BB%A4%E7%89%8C%E3%80%81Cookie%E3%80%81%E5%AD%A6%E6%A0%A1%E5%86%85%E5%AE%B9%E3%80%81%E8%B4%A6%E6%88%B7%E7%BD%91%E5%9D%80%E3%80%81%E5%8E%9F%E5%A7%8B+API+%E5%93%8D%E5%BA%94%E3%80%81%E5%BF%AB%E7%85%A7%E3%80%81%E5%87%AD%E6%8D%AE%E7%AE%A1%E7%90%86%E5%99%A8%E5%86%85%E5%AE%B9%E6%88%96%E7%A7%81%E4%BA%BA%E6%88%AA%E5%9B%BE%E3%80%82%0A%0A-+Release+tag+%2F+%E5%8F%91%E5%B8%83%E7%89%88%E6%9C%AC%EF%BC%9A%0A-+ZIP+SHA-256%EF%BC%9A%0A-+Windows+version+%2F+Windows+%E7%89%88%E6%9C%AC%EF%BC%9A%0A-+App+language+%2F+%E5%BA%94%E7%94%A8%E8%AF%AD%E8%A8%80%EF%BC%9A%0A-+Display+scaling+%2F+%E6%98%BE%E7%A4%BA%E7%BC%A9%E6%94%BE%EF%BC%9A%0A-+Failed+smoke-test+step+%2F+%E5%A4%B1%E8%B4%A5%E6%AD%A5%E9%AA%A4%EF%BC%9A%0A-+Failure+timing+%2F+%E5%A4%B1%E8%B4%A5%E6%97%B6%E9%97%B4%EF%BC%9A%0A-+Reproduction+steps+%2F+%E5%A4%8D%E7%8E%B0%E6%AD%A5%E9%AA%A4%EF%BC%9A%0A-+Observed+result+%2F+%E5%AE%9E%E9%99%85%E7%BB%93%E6%9E%9C%EF%BC%9A%0A-+Expected+result+%2F+%E9%A2%84%E6%9C%9F%E7%BB%93%E6%9E%9C%EF%BC%9A%0A%0A-+%5B+%5D+I+removed+all+sensitive+data+and+used+synthetic+data+for+screenshots.%0A-+%5B+%5D+%E6%88%91%E5%B7%B2%E7%A7%BB%E9%99%A4%E5%85%A8%E9%83%A8%E6%95%8F%E6%84%9F%E6%95%B0%E6%8D%AE%EF%BC%8C%E6%88%AA%E5%9B%BE%E5%8F%AA%E4%BD%BF%E7%94%A8%E5%90%88%E6%88%90%E6%95%B0%E6%8D%AE%E3%80%82), or use the same fields below.

Include:

- release tag and ZIP SHA-256;
- Windows version and x64 architecture;
- display scaling and selected language;
- the smoke-matrix step that failed;
- whether the failure occurred before setup, during read-only refresh, after restart, or offline;
- exact non-sensitive error category and reproducible actions.

Exclude tokens, cookies, URLs containing tenant or account details, course names, task titles, announcement text, raw API responses, the snapshot file, Credential Manager contents, and screenshots containing school data. Use synthetic preview data for screenshots whenever possible.
