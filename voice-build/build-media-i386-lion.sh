#!/bin/sh
# Build the static Opus and libsodium archives needed for Discord voice media
# on 32-bit Intel OS X 10.7. Run on the modern macOS cross-build host.
set -eu

: "${DISCORD_LITE_LEGACY_SDK:?DISCORD_LITE_LEGACY_SDK must be set}"
: "${LIBDAVE_SOURCE_DIR:?LIBDAVE_SOURCE_DIR must be set}"

# libsodium's release build regenerates its configure script. On the macOS
# build host install these once with: brew install autoconf automake libtool
command -v autoconf >/dev/null
command -v automake >/dev/null
command -v libtool >/dev/null

"$LIBDAVE_SOURCE_DIR/vcpkg/vcpkg" install \
    opus:i386-osx-107 \
    libsodium:i386-osx-107 \
    --overlay-triplets="$(cd "$(dirname "$0")" && pwd)/triplets"
