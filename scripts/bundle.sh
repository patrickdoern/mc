#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)/MC"
app="build/MC.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/MC"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp scripts/icon/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${MC_SIGN_IDENTITY:--}" "$app"
echo "$app"
