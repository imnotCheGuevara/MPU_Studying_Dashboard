#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
destination="${1:-$repository_root/dist}"
app_path="$destination/Campus Dashboard.app"
contents_path="$app_path/Contents"
binary_path="$repository_root/.build/$configuration/CampusDashboard"

cd "$repository_root"
swift build --configuration "$configuration" --jobs 1

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_path" "$contents_path/MacOS/CampusDashboard"
cp "$repository_root/Resources/Info.plist" "$contents_path/Info.plist"
chmod 755 "$contents_path/MacOS/CampusDashboard"

# Ad-hoc signing makes local builds deterministic and exercises the exact bundle
# identity. Distribution/development signing must replace this at Xcode adoption.
codesign --force --sign - \
  --identifier com.campusdashboard.desktop \
  --entitlements "$repository_root/Resources/CampusDashboard.entitlements" \
  --timestamp=none \
  "$app_path"

codesign --verify --deep --strict "$app_path"
echo "$app_path"
