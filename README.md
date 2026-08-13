# Discord Lite — legacy-build fork

An ultra-lightweight native Discord client for vintage and modern Macs.

This repository is the **CatSu-OSM fork** of [dosdude1/discord-lite](https://github.com/dosdude1/discord-lite). Its `master` branch contains compatibility work for building the client as an Intel application with **Xcode 4.6.3 on OS X 10.7 Lion**. It is not intended to be proposed back to the upstream project.

## What changed in this fork

The original project’s Interface Builder archives were written by a newer Xcode and could not be read by Xcode 4. The affected UI is now constructed in Objective-C instead of being compiled from XIB files.

- Main window, login, settings, CAPTCHA, attachment viewer, and two-factor UI are code-built.
- Server, channel, direct-message, chat-item, attachment-preview, tag-selection, and pending-attachment views are code-built.
- The main window, chat column, compose box, icons, and message metadata have legacy-Cocoa layout/styling fixes.
- Server icons remain round normally and change to rounded squares when selected.
- Image attachments are recognized by both Discord MIME type and common file extensions, including `.png`.

This removes the Xcode 4 error:

> The document "…ViewController.xib" could not be opened. Could not read archive.

## Requirements for legacy builds

- An **Intel Mac** running **OS X 10.6.8 Snow Leopard or later** to run the app. The build host remains OS X 10.7 Lion because it needs Xcode 4.6.3.
- **Xcode 4.6.3**.
- XcodeLegacy’s legacy compilers and the **Mac OS X 10.7 SDK** package for the 32-bit Intel build.

~~Use a modern Xcode version to compile the 32-bit build.~~ Modern Xcode versions reject `i386`; they cannot produce this project’s 32-bit Intel build. Apple Silicon Macs also cannot create 32-bit Intel binaries.

## Build on Lion / Xcode 4.6.3

1. Get this fork’s `master` branch. If the Lion-era Git client cannot connect to GitHub because of TLS, download the repository ZIP from GitHub on another machine and copy it to the Lion Mac.

2. Install Xcode 4.6.3 in `/Applications/Xcode.app`, launch it once, and accept its license.

3. Install XcodeLegacy with the legacy compiler and SDK packages. XcodeLegacy needs the Xcode 3.2.6 and Xcode 4.6.3 installer images available locally to build its packages. From the XcodeLegacy directory:

   ```sh
   sudo ./XcodeLegacy.sh -compilers -osx107 buildpackages
   sudo ./XcodeLegacy.sh -path=/Applications/Xcode.app -compilers -osx107 install
   ```

4. Open `Discord Lite.xcodeproj` in Xcode 4.6.3.

5. Select the **Discord Lite** target and choose the required Intel architecture:

   - `i386` for 32-bit Intel Macs.
   - `x86_64` for 64-bit Intel Macs.
   - A universal Intel configuration includes both slices.

6. Build and run with **Product → Build** or the Run button.

The project’s interface is code-built, so no XIB conversion or newer Interface Builder is needed.

## Minimum target

- Mac OS X 10.6.8 Snow Leopard on Intel (`i386` or `x86_64`)
- 256 MB RAM

The available features depend on Discord’s current API behavior and the target operating system. Text features target 10.6.8; modern Discord voice encryption needs C++17/libc++ and therefore has a separate 10.7 Intel baseline.

## Building the native voice encryption dependency

Discord's current voice encryption uses `libdave`.  The source in
`voice-build/` contains the fixed i386 Lion vcpkg triplet and an invocation
script.  Build it on a newer Intel Mac using an extracted `MacOSX10.7.sdk`:

```sh
export DISCORD_LITE_LEGACY_SDK=/path/to/MacOSX10.7.sdk
export LIBDAVE_SOURCE_DIR=/path/to/libdave/cpp
export PATH=/path/to/modern-cmake/bin:$PATH
sh voice-build/configure-libdave-i386-lion.sh
cmake --build "$LIBDAVE_SOURCE_DIR/build-i386-lion" --target libdave
```

This produces `build-i386-lion/libdave.a`, a static i386 archive suitable for
OS X 10.7.  It is a build prerequisite only: the client still needs the voice
WebSocket, UDP/RTP, Opus, microphone, and output integration before voice chat
is usable.

## Current functional state

### Works

- Servers and direct messages
- Text messages, replies, editing, deletion, mentions, typing status, and links
- Image and file attachments, including downloads
- Two-factor authentication and CAPTCHA flow
- SOCKS proxy settings

### Not implemented

- Voice audio streaming and video chat (selecting a voice channel sends the Discord join request, but media transport is not yet implemented)
- Message web embeds
- Friend requests

## Notes

- ~~The UI must be converted to an Xcode 4-compatible XIB/NIB format before a legacy build can succeed.~~ This fork replaces the affected XIB UI with Objective-C/Cocoa views.
- OS X 10.4 Intel runs 32-bit applications. If distributing a multi-architecture binary to Tiger Intel, remove the x86_64 slice with `lipo` if necessary.
- Upstream prebuilt releases and support remain available from [dosdude1/discord-lite releases](https://github.com/dosdude1/discord-lite/releases).
