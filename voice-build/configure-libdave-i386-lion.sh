#!/bin/sh
# Configure Discord's libdave for Intel 32-bit Lion.  Run this on a modern
# macOS host that has an Xcode 10.7 SDK copy in DISCORD_LITE_LEGACY_SDK.
set -eu

: "${DISCORD_LITE_LEGACY_SDK:?DISCORD_LITE_LEGACY_SDK must be set}"
: "${LIBDAVE_SOURCE_DIR:?LIBDAVE_SOURCE_DIR must be set}"
VOICE_BUILD_DIR=$(cd "$(dirname "$0")" && pwd)

cp "$VOICE_BUILD_DIR/lion-patches/persisted_key_pair_apple.cpp" \
   "$LIBDAVE_SOURCE_DIR/src/mls/detail/persisted_key_pair_apple.cpp"

cmake -S "$LIBDAVE_SOURCE_DIR" -B "$LIBDAVE_SOURCE_DIR/build-i386-lion" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=i386 \
    -DCMAKE_OSX_SYSROOT="$DISCORD_LITE_LEGACY_SDK" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.7 \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++ -D_LIBCPP_DISABLE_AVAILABILITY" \
    -DCMAKE_EXE_LINKER_FLAGS="-stdlib=libc++" \
    -DCMAKE_TOOLCHAIN_FILE="$LIBDAVE_SOURCE_DIR/vcpkg/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_MANIFEST_DIR="$LIBDAVE_SOURCE_DIR/vcpkg-alts/openssl_1.1" \
    -DVCPKG_OVERLAY_TRIPLETS="$VOICE_BUILD_DIR/triplets" \
    -DVCPKG_OVERLAY_PORTS="$VOICE_BUILD_DIR/ports" \
    -DVCPKG_TARGET_TRIPLET=i386-osx-107 \
    -DVCPKG_HOST_TRIPLET=x64-osx \
    -DBUILD_SHARED_LIBS=OFF \
    -DTESTING=OFF \
    -DPERSISTENT_KEYS=ON
