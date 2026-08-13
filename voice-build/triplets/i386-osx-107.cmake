# Static dependency triplet for the Lion-only native voice stack.
#
# The Discord UI continues to target OS X 10.6. Voice requires C++17/libc++,
# which Apple supports from OS X 10.7 onward, so these libraries deliberately
# have a separate 10.7 i386 baseline.
set(VCPKG_TARGET_ARCHITECTURE x86)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)

set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES i386)
set(VCPKG_OSX_DEPLOYMENT_TARGET 10.7)

if (NOT DEFINED ENV{DISCORD_LITE_LEGACY_SDK})
    message(FATAL_ERROR "Set DISCORD_LITE_LEGACY_SDK to a MacOSX10.7.sdk path before using i386-osx-107.")
endif()
set(VCPKG_OSX_SYSROOT "$ENV{DISCORD_LITE_LEGACY_SDK}")

set(VCPKG_C_FLAGS "-mmacosx-version-min=10.7")
set(VCPKG_CXX_FLAGS "-mmacosx-version-min=10.7 -stdlib=libc++")
set(VCPKG_LINKER_FLAGS "-mmacosx-version-min=10.7 -stdlib=libc++")
