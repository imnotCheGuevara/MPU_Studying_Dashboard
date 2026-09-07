#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
app_path="${1:-$repository_root/dist/Campus Dashboard.app}"
bundle_id="$(defaults read "$app_path/Contents/Info" CFBundleIdentifier)"

[[ "$bundle_id" == "com.campusdashboard.desktop" ]]
codesign --verify --deep --strict "$app_path"
codesign -d --entitlements - "$app_path" 2>&1 | grep -q 'com.apple.security.app-sandbox'

user_directory="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
probe_result="$user_directory/Library/Containers/com.campusdashboard.desktop/Data/Library/Application Support/com.campusdashboard.desktop/keychain-smoke-result.txt"
rm -f "$probe_result"
open -n -W "$app_path" --args --keychain-smoke-test keychain-smoke-result.txt
grep -qx 'PASS com.campusdashboard.desktop' "$probe_result"
rm -f "$probe_result"

echo "PASS $bundle_id: launched as a macOS application and completed the Keychain smoke test"
