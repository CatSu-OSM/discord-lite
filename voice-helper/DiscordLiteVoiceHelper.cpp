// Standalone 10.7+ Intel helper for Discord Lite voice media.
// Keep this out of the 10.6-targeted Cocoa application: DAVE requires libc++.
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioQueue.h>
#include <dave/dave.h>
#include <exception>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

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

struct CaptureTestState {
    unsigned long buffers;
    unsigned long bytes;
};

static void capturedPCM(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer,
                        const AudioTimeStamp *, UInt32, const AudioStreamPacketDescription *) {
    CaptureTestState *state = static_cast<CaptureTestState *>(userData);
    state->buffers++;
    state->bytes += buffer->mAudioDataByteSize;
    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

static int captureTest() {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 48000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;

    CaptureTestState state = { 0, 0 };
    AudioQueueRef queue = NULL;
    if (AudioQueueNewInput(&format, capturedPCM, &state, CFRunLoopGetCurrent(),
                           kCFRunLoopCommonModes, 0, &queue) != noErr) {
        fprintf(stderr, "Unable to open a 48 kHz stereo microphone stream.\n");
        return 7;
    }
    for (int index = 0; index < 3; index++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(queue, 3840, &buffer) != noErr) {
            AudioQueueDispose(queue, true);
            fprintf(stderr, "Unable to allocate microphone buffers.\n");
            return 8;
        }
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    }
    if (AudioQueueStart(queue, NULL) != noErr) {
        AudioQueueDispose(queue, true);
        fprintf(stderr, "Unable to start the microphone.\n");
        return 9;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);
    if (state.buffers == 0 || state.bytes == 0) {
        fprintf(stderr, "The microphone produced no PCM data.\n");
        return 10;
    }
    printf("Captured %lu bytes of 48 kHz stereo PCM in %lu buffers\n", state.bytes, state.buffers);
    return 0;
}

struct PlaybackTestState {
    long framesRemaining;
    double phase;
    unsigned long buffers;
};

static void playTone(void *userData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    PlaybackTestState *state = static_cast<PlaybackTestState *>(userData);
    const UInt32 frames = buffer->mAudioDataBytesCapacity / 4;
    short *samples = static_cast<short *>(buffer->mAudioData);
    for (UInt32 frame = 0; frame < frames; frame++) {
        short sample = 0;
        if (state->framesRemaining > 0) {
            sample = static_cast<short>(sin(state->phase) * 8000.0);
            state->phase += 2.0 * M_PI * 440.0 / 48000.0;
            state->framesRemaining--;
        }
        samples[frame * 2] = sample;
        samples[frame * 2 + 1] = sample;
    }
    buffer->mAudioDataByteSize = frames * 4;
    state->buffers++;
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

static int playbackTest() {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 48000;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;

    PlaybackTestState state = { 48000, 0.0, 0 };
    AudioQueueRef queue = NULL;
    if (AudioQueueNewOutput(&format, playTone, &state, CFRunLoopGetCurrent(),
                            kCFRunLoopCommonModes, 0, &queue) != noErr) {
        fprintf(stderr, "Unable to open a 48 kHz stereo speaker stream.\n");
        return 11;
    }
    for (int index = 0; index < 3; index++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(queue, 3840, &buffer) != noErr) {
            AudioQueueDispose(queue, true);
            return 12;
        }
        playTone(&state, queue, buffer);
    }
    if (AudioQueueStart(queue, NULL) != noErr) {
        AudioQueueDispose(queue, true);
        return 13;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.2, false);
    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);
    if (state.buffers < 3) return 14;
    printf("Played a 48 kHz stereo 440 Hz tone through %lu buffers\n", state.buffers);
    return 0;
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
    uint8_t *keyPackage = NULL;
    size_t keyPackageLength = 0;
    daveSessionGetMarshalledKeyPackage(session, &keyPackage, &keyPackageLength);
    if (!keyPackage || keyPackageLength == 0) {
        if (keyPackage) daveFree(keyPackage);
        daveSessionDestroy(session);
        fprintf(stderr, "DAVE could not create a persistent signing identity.\n");
        return 5;
    }
    daveFree(keyPackage);
    DAVEEncryptorHandle encryptor = daveEncryptorCreate();
    DAVEDecryptorHandle decryptor = daveDecryptorCreate();
    const bool okay = encryptor && decryptor;
    if (encryptor) daveEncryptorDestroy(encryptor);
    if (decryptor) daveDecryptorDestroy(decryptor);
    daveSessionDestroy(session);
    if (!okay) {
        fprintf(stderr, "Unable to create DAVE media cryptors.\n");
        return 6;
    }
    printf("DAVE protocol %u; input device %u; output device %u\n", version, (unsigned)input, (unsigned)output);
    return 0;
}

static void printHex(const uint8_t *data, size_t length) {
    static const char hex[] = "0123456789abcdef";
    for (size_t index = 0; index < length; index++) {
        putchar(hex[data[index] >> 4]);
        putchar(hex[data[index] & 15]);
    }
    putchar('\n');
}

static int keyPackage(const char *userID, const char *groupID) {
    char *end = NULL;
    const unsigned long long group = strtoull(groupID, &end, 10);
    if (!userID[0] || !groupID[0] || !end || *end) return 15;
    DAVESessionHandle session = daveSessionCreate(NULL, userID, daveFailure, NULL);
    if (!session) return 16;
    daveSessionInit(session, daveMaxSupportedProtocolVersion(), (uint64_t)group, userID);
    uint8_t *package = NULL;
    size_t length = 0;
    daveSessionGetMarshalledKeyPackage(session, &package, &length);
    if (!package || !length) {
        if (package) daveFree(package);
        daveSessionDestroy(session);
        return 17;
    }
    printHex(package, length);
    daveFree(package);
    daveSessionDestroy(session);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--dave-version") == 0) {
        printf("%u\n", daveMaxSupportedProtocolVersion());
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--capture-test") == 0) return captureTest();
    if (argc == 2 && strcmp(argv[1], "--playback-test") == 0) return playbackTest();
    if (argc == 4 && strcmp(argv[1], "--key-package") == 0) return keyPackage(argv[2], argv[3]);
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "--self-test") == 0)) return selfTest();
    fprintf(stderr, "Usage: %s [--self-test|--dave-version|--capture-test|--playback-test|--key-package USER_ID GROUP_ID]\n", argv[0]);
    return 64;
}
