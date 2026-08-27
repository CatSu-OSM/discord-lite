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

The `voice-helper/` directory is that separate 10.7+ component. It keeps
Discord's DAVE encryption library and CoreAudio out of the Snow-Leopard
application target. Its bundled dependencies build a universal i386/x86_64
`DiscordLiteVoiceHelper`; run `sh voice-helper/build-lion-helper.sh` on Lion
to build and exercise its DAVE and audio-device self-test.
Run `voice-helper/build/DiscordLiteVoiceHelper --capture-test` to open the
default microphone at Discord's required 48 kHz stereo PCM format for one
second and report the captured data.
Run `--playback-test` for a one-second 440 Hz speaker tone at the same format.
The helper also exposes `--key-package USER_ID GROUP_ID`, which emits the
hex-encoded MLS key package consumed by Discord Voice Opcode 26.
For the app's 10.7+ DAVE control bridge, `--dave-service` keeps the MLS
session alive over a newline-delimited stdin/stdout protocol. It supports
initial key-package generation plus external-sender, proposal, commit, and
welcome processing without loading libdave into the 10.6-compatible app.
Once an MLS epoch is active, its `ACTIVATE AUDIO_SSRC VIDEO_SSRC`,
`ENCRYPT AUDIO_SSRC HEX`, and `ENCRYPT_VIDEO VIDEO_SSRC HEX` commands bind the
sender ratchet to Opus and H.264 media. Incoming audio uses a per-user DAVE
decryptor. The helper also self-decrypts the first outgoing encrypted video
frame so a DAVE framing or ratchet mismatch fails before invalid media is sent.

The helper's DAVE build uses the OS X Keychain to retain the device's signing
identity. It is therefore a 10.7+ helper feature; the 10.6.8 text target does
not link against it.

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
OS X 10.7. The app delegates DAVE/MLS work to the bundled helper so the main
10.6-compatible Objective-C target does not need to load the C++17 library.

### Media dependencies

Voice media also requires static Opus and libsodium archives. On the modern
cross-build host, install the one-time configure prerequisites and run:

```sh
brew install autoconf automake libtool
export DISCORD_LITE_LEGACY_SDK=/path/to/MacOSX10.7.sdk
export LIBDAVE_SOURCE_DIR=/path/to/libdave/cpp
sh voice-build/build-media-i386-lion.sh
```

The resulting `libopus.a` and `libsodium.a` are installed below
`$LIBDAVE_SOURCE_DIR/vcpkg/installed/i386-osx-107/lib/`.

This fork also includes the resulting universal Intel (`i386` and `x86_64`)
Opus and libsodium archives in `Discord Lite/VoiceDependencies/`.  Xcode 4.6.3
links those archives automatically; building the application does not require
Homebrew or vcpkg on the Lion Mac.  They support the 10.7+ voice path only and
do not change the 10.6.8 text-client baseline.

## How voice audio and camera video work

Getting current Discord media working on Lion required implementing each layer
explicitly while retaining the 10.6 deployment target for the text client.

### Voice connection and encryption

- Joining a channel sends the main Gateway voice-state update, opens the Voice
  WebSocket, performs heartbeat/identify/resume handling, and negotiates the
  Opus and H.264 codecs plus Discord's
  `aead_xchacha20_poly1305_rtpsize` UDP transport.
- UDP discovery leaves its socket connected to the Discord voice edge. Lion
  must send subsequent RTP with `send()`; `sendto()` fails with `EISCONN` and
  silently prevents microphone or camera packets from leaving the client.
- Discord's mandatory DAVE E2EE is handled by the bundled 10.7+ helper. It
  maintains the MLS epoch, persistent Keychain-backed signing identity,
  sender/receiver ratchets, and Opus/H.264 frame encryption outside the
  Snow-Leopard-compatible app process.
- Helper commands are serialized because audio and camera callbacks can arrive
  on different threads. Media does not start until the DAVE ratchet is active.

### Audio path

- Core Audio `AudioQueue` captures and plays signed 16-bit, 48 kHz stereo PCM.
  Input callbacks are created on the main thread on Lion, whose curl worker
  does not drive a CFRunLoop. Partial input buffers are combined into exact
  20 ms / 960-frame blocks before Opus encoding.
- The client sends Discord's Speaking update before the first encrypted RTP
  packet, applies DAVE to the Opus frame, then applies RTP-size XChaCha20
  transport encryption. Incoming packets reverse that process and are decoded
  to PCM for `AudioQueue` playback.
- Packets that arrive before a Speaking event identifies their SSRC are held in
  a bounded queue. Voice generations prevent packets and callbacks from an old
  connection from leaking into a rejoin.

### Camera path

- The Start Camera button opens Lion's built-in iSight through QTKit and shows
  a local `QTCaptureView` preview. QuickTime `ICMCompressionSession` encodes
  320x240 H.264 at 15 fps, with frame reordering disabled. The target links
  `QTKit.framework`, `QuickTime.framework`, and `CoreVideo.framework`, and the
  app declares its camera-use description.
- QuickTime's AVCC output is converted to Annex B and keyframes include SPS and
  PPS NAL units. Lion's encoder omits WebRTC's decoder bitstream restrictions;
  the SPS VUI is rewritten to require zero reordered frames and a reference-
  sized decoder buffer. Without that rewrite, the receiving Discord client
  rejects the camera with error 2012 even though the H.264 bitstream itself is
  independently decodable.
- Camera negotiation uses Voice v8 stream RID `100` with type `video` in both
  Identify and Voice Opcode 12. Type `screen` is reserved for a separate Go
  Live connection and does not create a usable camera route.
- The assigned video and RTX SSRCs are bound to DAVE's H.264 codec. Encrypted
  Annex-B frames are packetized as H.264 RTP payload type 101, with FU-A
  fragmentation for large NAL units, receiver playout-delay extension ID 6,
  and marker bits on the final packet of a frame.
- Encrypted RTCP sender reports are emitted once per second. Incoming RTCP
  payload-specific feedback requests a fresh SPS/PPS/IDR keyframe so a viewer
  can join or recover after packet loss.

## Known issue

The call/voice UI layout is currently broken after the media work. This is a
separate UI regression; it does not indicate that the audio or camera transport
failed. The layout needs a follow-up repair while preserving the working media
pipeline.

## Current functional state

### Works

- Servers and direct messages
- Text messages, replies, editing, deletion, mentions, typing status, and links
- Image and file attachments, including downloads
- Two-factor authentication and CAPTCHA flow
- SOCKS proxy settings
- Voice-channel audio capture, encrypted transmission, receive, and playback
- Camera preview and encrypted H.264 camera transmission from Lion

### Not implemented

- Receiving and displaying other users' camera video in Discord Lite
- Screen sharing / Go Live
- Message web embeds
- Friend requests

## Notes

- ~~The UI must be converted to an Xcode 4-compatible XIB/NIB format before a legacy build can succeed.~~ This fork replaces the affected XIB UI with Objective-C/Cocoa views.
- OS X 10.4 Intel runs 32-bit applications. If distributing a multi-architecture binary to Tiger Intel, remove the x86_64 slice with `lipo` if necessary.
- Upstream prebuilt releases and support remain available from [dosdude1/discord-lite releases](https://github.com/dosdude1/discord-lite/releases).
