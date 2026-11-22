#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/Moonlight Commander.app"
dmg="${1:-build/mc.dmg}"
staging="$(mktemp -d)"
writable="$staging.dmg"
volume=""
trap '[[ -n "$volume" ]] && hdiutil detach -quiet "$volume" || true; rm -rf "$staging" "$writable"' EXIT
rm -f "$dmg"
ditto "$app" "$staging/${app:t}"
ln -s /Applications "$staging/Applications"
mkdir "$staging/.background"
cp scripts/dmg-background.tiff "$staging/.background/background.tiff"
hdiutil create -quiet -volname "Moonlight Commander" -srcfolder "$staging" -fs HFS+ -format UDRW "$writable"
volume="$(hdiutil attach -readwrite -noverify -noautoopen "$writable" | awk -F'\t' '/\/Volumes\// { print $NF }')"
osascript - "${volume:t}" "${app:t}" <<'APPLESCRIPT'
on run {diskName, appName}
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 120, 840, 548}
            set options to icon view options of container window
            set arrangement of options to not arranged
            set icon size of options to 128
            set text size of options to 13
            set background picture of options to file ".background:background.tiff"
            set position of item appName of container window to {160, 185}
            set position of item "Applications" of container window to {480, 185}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT
sync
hdiutil detach -quiet "$volume"
volume=""
hdiutil convert -quiet "$writable" -format UDZO -o "$dmg"
echo "$dmg"
