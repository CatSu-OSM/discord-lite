// Standalone 10.7+ Intel helper for Discord Lite voice media.
// Keep this out of the 10.6-targeted Cocoa application: DAVE requires libc++.
#include <CoreAudio/CoreAudio.h>
#include <dave/dave.h>
#include <exception>
#include <stdio.h>
#include <string.h>

// Xcode 4's Lion libc++ predates std::variant. The prebuilt DAVE stack uses
// this C++17 exception ABI, so provide the two symbols it needs.
namespace std {
class bad_variant_access : public exception {
public:
    bad_variant_access() throw();
    virtual ~bad_variant_access() throw();
    virtual const char *what() const throw();
};

bad_variant_access::bad_variant_access() throw() {}
bad_variant_access::~bad_variant_access() throw() {}
const char *bad_variant_access::what() const throw() { return "bad variant access"; }

inline namespace __1 {
void __throw_bad_variant_access() { throw bad_variant_access(); }
}
}

static void daveFailure(const char *source, const char *reason, void *) {
    fprintf(stderr, "DAVE failure from %s: %s\n", source ? source : "unknown", reason ? reason : "unknown");
}

static bool defaultDevice(const AudioObjectPropertySelector selector, AudioDeviceID *device) {
    AudioObjectPropertyAddress address = { selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
    UInt32 size = sizeof(*device);
    return AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, device) == noErr && *device != kAudioObjectUnknown;
}

static int selfTest() {
    AudioDeviceID input = kAudioObjectUnknown;
    AudioDeviceID output = kAudioObjectUnknown;
    if (!defaultDevice(kAudioHardwarePropertyDefaultInputDevice, &input)) {
        fprintf(stderr, "No default input device is available.\n");
        return 2;
    }
    if (!defaultDevice(kAudioHardwarePropertyDefaultOutputDevice, &output)) {
        fprintf(stderr, "No default output device is available.\n");
        return 3;
    }

    DAVESessionHandle session = daveSessionCreate(NULL, "discord-lite-self-test", daveFailure, NULL);
    if (!session) {
        fprintf(stderr, "Unable to create a DAVE session.\n");
        return 4;
    }
    const uint16_t version = daveMaxSupportedProtocolVersion();
    daveSessionInit(session, version, 1, "0");
    DAVEEncryptorHandle encryptor = daveEncryptorCreate();
    DAVEDecryptorHandle decryptor = daveDecryptorCreate();
    const bool okay = encryptor && decryptor;
    if (encryptor) daveEncryptorDestroy(encryptor);
    if (decryptor) daveDecryptorDestroy(decryptor);
    daveSessionDestroy(session);
    if (!okay) {
        fprintf(stderr, "Unable to create DAVE media cryptors.\n");
        return 5;
    }
    printf("DAVE protocol %u; input device %u; output device %u\n", version, (unsigned)input, (unsigned)output);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--dave-version") == 0) {
        printf("%u\n", daveMaxSupportedProtocolVersion());
        return 0;
    }
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "--self-test") == 0)) return selfTest();
    fprintf(stderr, "Usage: %s [--self-test|--dave-version]\n", argv[0]);
    return 64;
}
