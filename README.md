# Discord Lite — legacy-build fork

An ultra-lightweight native Discord client for vintage and modern Macs.

This repository is the **CatSu-OSM fork** of [dosdude1/discord-lite](https://github.com/dosdude1/discord-lite). Its `master` branch contains compatibility work for building the client as a 32-bit Intel / PowerPC application with **Xcode 4.6.3 on OS X 10.7 Lion**. It is not intended to be proposed back to the upstream project.

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

- An **Intel Mac** running **OS X 10.7 Lion**.
- **Xcode 4.6.3**.
- XcodeLegacy’s legacy compilers and the **Mac OS X 10.5** and **10.7 SDK** packages for PowerPC/older-Intel targets.

~~Use a modern Xcode version to compile the 32-bit build.~~ Modern Xcode versions reject `i386`; they cannot produce this project’s 32-bit Intel build. Apple Silicon Macs also cannot create PowerPC or 32-bit Intel binaries.

## Build on Lion / Xcode 4.6.3

1. Get this fork’s `master` branch. If the Lion-era Git client cannot connect to GitHub because of TLS, download the repository ZIP from GitHub on another machine and copy it to the Lion Mac.

2. Install Xcode 4.6.3 in `/Applications/Xcode.app`, launch it once, and accept its license.

3. Install XcodeLegacy with the legacy compiler and SDK packages. XcodeLegacy needs the Xcode 3.2.6 and Xcode 4.6.3 installer images available locally to build its packages. From the XcodeLegacy directory:

   ```sh
   sudo ./XcodeLegacy.sh -compilers -osx105 -osx107 buildpackages
   sudo ./XcodeLegacy.sh -path=/Applications/Xcode.app -compilers -osx105 -osx107 install
   ```

4. Open `Discord Lite.xcodeproj` in Xcode 4.6.3.

5. Select the **Discord Lite** target and choose the required architecture:

   - `i386` for 32-bit Intel Macs.
   - `ppc` for PowerPC Macs.
   - A universal configuration only when every selected architecture and SDK is installed.

6. Build and run with **Product → Build** or the Run button.

The project’s interface is code-built, so no XIB conversion or newer Interface Builder is needed.

## Minimum target

- Mac OS X 10.4 Tiger
- PowerPC G3 or Intel processor
- 256 MB RAM

The available features depend on Discord’s current API behavior and the target operating system. CAPTCHA support requires OS X 10.5 or later.

## Current functional state

### Works

- Servers and direct messages
- Text messages, replies, editing, deletion, mentions, typing status, and links
- Image and file attachments, including downloads
- Two-factor authentication and CAPTCHA flow
- SOCKS proxy settings

### Not implemented

- Voice and video chat
- Message web embeds
- Friend requests

## Notes

- ~~The UI must be converted to an Xcode 4-compatible XIB/NIB format before a legacy build can succeed.~~ This fork replaces the affected XIB UI with Objective-C/Cocoa views.
- OS X 10.4 Intel runs 32-bit applications. If distributing a multi-architecture binary to Tiger Intel, remove the x86_64 slice with `lipo` if necessary.
- Upstream prebuilt releases and support remain available from [dosdude1/discord-lite releases](https://github.com/dosdude1/discord-lite/releases).
