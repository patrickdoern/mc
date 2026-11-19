#!/bin/zsh
# Legt website/ auf janus ab. Der DMG liegt als GitHub-Release, nicht auf dem Server.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${MC_WEB_HOST:-janus-root}"
target=/var/www/moonlight-commander.de
rsync -a --delete --exclude .DS_Store --exclude mc.dmg website/ "$host:$target/"
ssh "$host" "chown -R root:root $target && find $target -type d -exec chmod 755 {} + && find $target -type f -exec chmod 644 {} +"
echo "https://moonlight-commander.de"
