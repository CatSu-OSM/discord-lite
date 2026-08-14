# Static dependency triplet for 64-bit Intel voice support on OS X 10.7+.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)

set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES x86_64)
set(VCPKG_OSX_DEPLOYMENT_TARGET 10.7)

if (NOT DEFINED ENV{DISCORD_LITE_LEGACY_SDK})
    message(FATAL_ERROR "Set DISCORD_LITE_LEGACY_SDK to a MacOSX10.7.sdk path before using x64-osx-107.")
endif()
set(VCPKG_OSX_SYSROOT "$ENV{DISCORD_LITE_LEGACY_SDK}")

set(VCPKG_C_FLAGS "-mmacosx-version-min=10.7")
set(VCPKG_CXX_FLAGS "-mmacosx-version-min=10.7 -stdlib=libc++ -D_LIBCPP_DISABLE_AVAILABILITY")
set(VCPKG_LINKER_FLAGS "-mmacosx-version-min=10.7 -stdlib=libc++")
set(VCPKG_CMAKE_CONFIGURE_OPTIONS
    "-DCMAKE_CXX_FLAGS:STRING=-mmacosx-version-min=10.7 -stdlib=libc++ -D_LIBCPP_DISABLE_AVAILABILITY"
    "-DCMAKE_EXE_LINKER_FLAGS:STRING=-mmacosx-version-min=10.7 -stdlib=libc++"
    "-DCMAKE_SHARED_LINKER_FLAGS:STRING=-mmacosx-version-min=10.7 -stdlib=libc++")
