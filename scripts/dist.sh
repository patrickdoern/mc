#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MC_SIGN_IDENTITY:?Developer-ID-Application-Identität in MC_SIGN_IDENTITY setzen}"
: "${MC_NOTARY_PROFILE:?notarytool-Profil in MC_NOTARY_PROFILE setzen (xcrun notarytool store-credentials)}"
./scripts/bundle.sh
dmg="build/mc.dmg"
rm -f build/Moonlight-Commander.dmg
./scripts/make-dmg.sh "$dmg"
codesign --force --sign "$MC_SIGN_IDENTITY" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$MC_NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
echo "$dmg"
