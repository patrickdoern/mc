#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-libssh2.sh
./scripts/bundle.sh
target="/Applications/macOS Commander.app"
rm -rf "$target"
ditto build/MC.app "$target"
echo "$target"
