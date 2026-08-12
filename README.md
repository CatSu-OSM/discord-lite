# Discord Lite

### An ultra-lightweight native Discord client for vintage and modern Mac OS

![screenshot1](https://raw.githubusercontent.com/dosdude1/discord-lite/master/res/screenshot1.png)

### Minimum System Requirements

- Mac OS X version 10.4 (Tiger)
- PowerPC G3 CPU
- 256MB of system memory


### Current Functional State

#### What Works

- Viewing and interaction in both servers and direct messages
- Sending images and attachments
- Viewing and downloading images and attachments
- Mention/ping notifications
- Pinging users
- Typing indication
- Viewing and sending replies
- URL hotlinks
- Two-factor authentication
- Captchas (in Mac OS X 10.5 or later only)
- Editing messages
- Deleting messages


#### What does not work

(I plan to implement all the following unless noted otherwise)

- Message web embeds
- Voice and video chat
- Friend requests (will not be implemented due to Discord TOS concerns)


### Important Notes

- As of version 0.3-alpha, a new Curl and OpenSSL-based backend for both the WebSocket and HTTP requests has been implemented. As such, the application now has full TLS v1.3 support, and once again works without the need of going through a proxy running on a newer machine.
- OS X 10.4 Tiger on Intel can only run 32-bit applications, but will try to load the 64-bit slice of the FAT binary. To work around this, you need to "thin" the binary for i386 (or remove the x86_64 slice) using "lipo".


### Releases

Prebuilt Universal "Quad-FAT" binaries can be found in the [Releases](https://github.com/dosdude1/discord-lite/releases) section. You can download and run on PowerPC, 32-bit Intel, 64-bit Intel, or ARM (Apple Silicon) Macs.

Alternatively, you can download the latest release off [my website](http://dosdude1.com/apps/Discord%20Lite.dmg), which is loadable on the older machines.


### Building

~~You can use a modern Xcode version to build this application, but installing legacy SDKs and compilers is necessary using [Xcode Legacy](https://github.com/devernay/xcodelegacy) to compile for older architectures.~~

Building the universal release (`ppc`, `i386`, and `x86_64`) requires an **Intel Mac**, **Xcode 12.5.1**, and [XcodeLegacy](https://github.com/devernay/xcodelegacy). Xcode 13 and newer reject the `i386` architecture. Apple Silicon Macs cannot produce the PowerPC or 32-bit Intel slices.

Install Xcode 12.5.1 as `/Applications/Xcode.app`, open it once to accept its licence and install its components, then quit it. Download the following legacy Xcode disk images from the Apple Developer Downloads portal and place them beside `XcodeLegacy.sh`:

- Xcode 3.2.6 (`xcode_3.2.6_and_ios_sdk_4.3.dmg`) for GCC 4.2 and the Mac OS X 10.5 SDK
- Xcode 4.6.3 (`Xcode_4.6.3.dmg`) for the Mac OS X 10.7 SDK

Extract the XcodeLegacy packages:

```bash
chmod +x XcodeLegacy.sh
./XcodeLegacy.sh -path=/Applications/Xcode.app -compilers -osx105 -osx107 buildpackages
```

Xcode 12 stores its architecture specification in a different location than the one expected by XcodeLegacy. Before installation, patch the script and keep a backup:

```bash
cp XcodeLegacy.sh XcodeLegacy.sh.backup
sed -i '' 's|Developer/Library/Xcode/Specifications/MacOSX Architectures.xcspec|Developer/Library/Xcode/PrivatePlugIns/IDEOSXSupportCore.ideplugin/Contents/Resources/MacOSX Architectures.xcspec|g' XcodeLegacy.sh
```

Install the legacy components:

```bash
sudo ./XcodeLegacy.sh -path=/Applications/Xcode.app -compilers -osx105 -osx107 install
```

~~Once Xcode Legacy components have been installed, the application can simply be built and run in Xcode.~~ Xcode 12 cannot load XcodeLegacy's old GCC compiler plug-ins. After installation, move those plug-ins out of Xcode; the GCC 4.2 executable remains available and the project invokes it directly for the Release target:

```bash
sudo mkdir -p '/Users/YOUR_USERNAME/Downloads/XcodeLegacy-disabled-plugins'
sudo mv '/Applications/Xcode.app/Contents/PlugIns/Xcode3Core.ideplugin/Contents/SharedSupport/Developer/Library/Xcode/Plug-ins/GCC 4.0.xcplugin' '/Users/YOUR_USERNAME/Downloads/XcodeLegacy-disabled-plugins/'
sudo mv '/Applications/Xcode.app/Contents/PlugIns/Xcode3Core.ideplugin/Contents/SharedSupport/Developer/Library/Xcode/Plug-ins/GCC 4.2.xcplugin' '/Users/YOUR_USERNAME/Downloads/XcodeLegacy-disabled-plugins/'
sudo mv '/Applications/Xcode.app/Contents/PlugIns/Xcode3Core.ideplugin/Contents/SharedSupport/Developer/Library/Xcode/Plug-ins/LLVM GCC 4.2.xcplugin' '/Users/YOUR_USERNAME/Downloads/XcodeLegacy-disabled-plugins/'
```

If one of the move commands says `No such file or directory`, that plug-in was already absent and can be ignored.

Restart Xcode, open `Discord Lite.xcodeproj`, select the **Release** build configuration, choose **Product > Clean Build Folder**, then build. The Release configuration calls `gcc-4.2`/`g++-4.2`, uses the 10.5 SDK for PowerPC and the 10.7 SDK for i386, and uses DWARF debug information because modern `dsymutil` cannot process PowerPC binaries.

**Note:** In order to compile a working Intel 64-bit binary for OS X 10.5 Leopard, you must either build with the 10.5 SDK itself, or use the CoreFoundation and Foundation framework binaries from the 10.5 SDK in a later SDK.
