#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
vendor="$PWD/vendor"
work="$vendor/work"
openssl_version=4.1.0
openssl_sha=50c17baf54cb008f6ce42d50deb4b28050a1aad711636cabd4b241c7e90cc2fd
libssh2_version=1.11.1
libssh2_sha=d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7
export MACOSX_DEPLOYMENT_TARGET=14.0

if [[ -f "$vendor/lib/libssh2.a" && "${1:-}" != "--force" ]]; then
    echo "vendor/lib/libssh2.a vorhanden (neu bauen mit --force)"
    exit 0
fi

rm -rf "$vendor"
mkdir -p "$work"
cd "$work"

fetch() {
    curl -fsSL -o "$2" "$1"
    echo "$3  $2" | shasum -a 256 -c -
    tar xf "$2"
}

fetch "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz" openssl.tar.gz "$openssl_sha"
(
    cd "openssl-$openssl_version"
    ./Configure darwin64-arm64-cc no-shared no-tests --prefix="$vendor" --openssldir="$vendor/ssl" -mmacosx-version-min=14.0
    make -j"$(sysctl -n hw.ncpu)"
    make install_sw
)

fetch "https://libssh2.org/download/libssh2-$libssh2_version.tar.gz" libssh2.tar.gz "$libssh2_sha"
(
    cd "libssh2-$libssh2_version"
    ./configure --prefix="$vendor" --disable-shared --enable-static --with-crypto=openssl --with-libssl-prefix="$vendor" \
        --disable-examples-build --disable-docker-tests CFLAGS="-mmacosx-version-min=14.0 -O2"
    make -j"$(sysctl -n hw.ncpu)"
    make install
)

rm -rf "$work"
echo "$vendor/lib/libssh2.a"
