#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-libssh2.sh
./scripts/bundle.sh
target="/Applications/Moonlight Commander.app"
rm -rf "/Applications/macOS Commander.app" "$target"
ditto "build/Moonlight Commander.app" "$target"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
mkdir -p "$HOME/.local/bin"
install -m 755 scripts/mc scripts/mcedit "$HOME/.local/bin/"
echo "$target, $HOME/.local/bin/mc, $HOME/.local/bin/mcedit"
