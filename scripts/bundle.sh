#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)/MC"
app="build/MC.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/MC"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"
