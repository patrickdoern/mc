#!/bin/zsh
# Legt website/ und (falls vorhanden) das notarisierte build/mc.dmg auf janus ab.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${MC_WEB_HOST:-janus-root}"
target=/var/www/moonlight-commander.de
rsync -a --delete --exclude .DS_Store --exclude mc.dmg website/ "$host:$target/"
if [[ -f build/mc.dmg ]]; then rsync -a build/mc.dmg "$host:$target/mc.dmg"; fi
ssh "$host" "chown -R root:root $target && find $target -type d -exec chmod 755 {} + && find $target -type f -exec chmod 644 {} +"
echo "https://moonlight-commander.de"
