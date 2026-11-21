#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
identity="${MC_SIGN_IDENTITY:--}"
swift build -c release
bin="$(swift build -c release --show-bin-path)/MC"
app="build/Moonlight Commander.app"
frameworks="$app/Contents/Frameworks"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$frameworks"
cp "$bin" "$app/Contents/MacOS/MC"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp Sources/MC/Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R Sources/MC/Resources/en.lproj "$app/Contents/Resources/en.lproj"

external_dependencies() {
    otool -L "$1" | awk 'NR > 1 && ($1 ~ /^\/opt\/homebrew\// || $1 ~ /^\/usr\/local\//) { print $1 }'
}

queue=("$app/Contents/MacOS/MC")
minos=14.0
while (( ${#queue[@]} )); do
    file="${queue[1]}"
    queue=("${queue[@]:1}")
    for dependency in $(external_dependencies "$file"); do
        name="${dependency:t}"
        if [[ ! -f "$frameworks/$name" ]]; then
            cp "$(realpath "$dependency")" "$frameworks/$name"
            chmod u+w "$frameworks/$name"
            install_name_tool -id "@executable_path/../Frameworks/$name" "$frameworks/$name"
            queue+=("$frameworks/$name")
            library_minos="$(vtool -show-build "$frameworks/$name" | awk '/minos/ { print $2; exit }')"
            if [[ "$(printf '%s\n%s\n' "$minos" "$library_minos" | sort -V | tail -1)" != "$minos" ]]; then minos="$library_minos"; fi
        fi
        install_name_tool -change "$dependency" "@executable_path/../Frameworks/$name" "$file"
    done
done

/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $minos" "$app/Contents/Info.plist"

sign_flags=()
if [[ "$identity" != "-" ]]; then sign_flags=(--options runtime --timestamp); fi
for library in "$frameworks"/*.dylib(N); do
    codesign --force --sign "$identity" "${sign_flags[@]}" "$library"
done
codesign --force --sign "$identity" "${sign_flags[@]}" "$app"
echo "$app (macOS ab $minos)"
