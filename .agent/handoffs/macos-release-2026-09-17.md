# macOS 0.3.1 (5) distribution

Status: PARTIAL — local gates passed; publication verification pending.

User authorized publishing the repaired current Mac version and replacing obsolete downloads. No existing macOS GitHub release asset was found; existing assets are Windows-only and must stay intact.

Includes the existing DeepSeek model repair and progress/error display, manual events, and existing SIweb session lifecycle/sync fixes. Preserves all prior work. Version metadata changed to 0.3.1 (5). Source snapshot is committed on a dedicated release branch.

Validation: scripts/test.sh — 250 tests / 21 suites PASS; scripts/build-app.sh dist/macos-0.3.1 — PASS; scripts/verify-app.sh with absolute candidate path — PASS including packaged Keychain smoke; strict signing and git diff --check — PASS. Logs are /tmp/campus-macos-release-{tests,build,verify}.log. No live school reads, provider requests, consent grants or Calendar writes were performed.

Distribution: Apple Silicon arm64, macOS 14+, ad-hoc signed and not Apple-notarized. Existing in-app credentials are not bundled. Users must renew DeepSeek model consent and reprocess failed announcements after updating. Friend-machine launch and live DeepSeek acceptance remain pending. Canvas configuration-state confusion reported in this conversation is not claimed fixed by this release.
