#!/bin/sh
# Build the separate 10.7+ Intel voice helper using Xcode 4.6.3 or newer.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SDK=${DISCORD_LITE_LEGACY_SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.7.sdk}
CXX=${CXX:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++}
INCLUDE="$SCRIPT_DIR/Dependencies/include"
LIB="$SCRIPT_DIR/Dependencies/lib"
OUT="$SCRIPT_DIR/build"

mkdir -p "$OUT"
for ARCH in i386 x86_64; do
    "$CXX" -arch "$ARCH" -std=c++11 -stdlib=libc++ -mmacosx-version-min=10.7 -isysroot "$SDK" \
        -I"$INCLUDE" "$SCRIPT_DIR/DiscordLiteVoiceHelper.cpp" -L"$LIB" \
        -ldave -lmlspp -lmls_ds -ltls_syntax -lbytes -lhpke -lcrypto -lc++ \
        -framework AudioToolbox -framework CoreAudio -framework CoreFoundation -framework Security \
        -o "$OUT/DiscordLiteVoiceHelper-$ARCH"
done
lipo -create "$OUT/DiscordLiteVoiceHelper-i386" "$OUT/DiscordLiteVoiceHelper-x86_64" \
    -output "$OUT/DiscordLiteVoiceHelper"
chmod +x "$OUT/DiscordLiteVoiceHelper"
"$OUT/DiscordLiteVoiceHelper" --self-test
