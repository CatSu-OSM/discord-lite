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
#include <vector>
#include <string>
#include <map>

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

// libdave's default diagnostic sink writes to stdout.  Stdout is the framing
// channel for --dave-service, so route diagnostics to stderr instead.
static void daveLog(DAVELoggingSeverity severity, const char *file, int line, const char *message) {
    if (severity >= DAVE_LOGGING_SEVERITY_WARNING) {
        fprintf(stderr, "DAVE %s:%d: %s\n", file ? file : "unknown", line, message ? message : "unknown");
    }
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

static bool decodeHex(const char *text, std::vector<uint8_t> *output) {
    size_t length = strlen(text);
    if ((length & 1) != 0) return false;
    output->clear();
    output->reserve(length / 2);
    for (size_t index = 0; index < length; index += 2) {
        char pair[3] = { text[index], text[index + 1], 0 };
        char *end = NULL;
        unsigned long value = strtoul(pair, &end, 16);
        if (!end || *end || value > 255) return false;
        output->push_back((uint8_t)value);
    }
    return true;
}

static void printResponse(const char *status) {
    printf("%s\n", status);
    fflush(stdout);
}

static void printHexResponse(const char *status, const uint8_t *data, size_t length) {
    printf("%s ", status);
    static const char hex[] = "0123456789abcdef";
    for (size_t index = 0; index < length; index++) {
        putchar(hex[data[index] >> 4]);
        putchar(hex[data[index] & 15]);
    }
    putchar('\n');
    fflush(stdout);
}

static void splitUserIDs(char *text, std::vector<const char *> *users) {
    users->clear();
    if (!text || !*text || strcmp(text, "-") == 0) return;
    users->push_back(text);
    for (char *cursor = text; *cursor; cursor++) {
        if (*cursor == ',') {
            *cursor = 0;
            users->push_back(cursor + 1);
        }
    }
}

// A newline-delimited, local-only control protocol.  It deliberately accepts
// hex rather than raw websocket bytes so the 10.6 Cocoa process can exchange
// DAVE data over NSPipe without linking libdave or requiring C++17.
//
// INIT USER_ID GROUP_ID      -> KEY_PACKAGE <hex>
// EXTERNAL_SENDER <hex>      -> OK
// PROPOSALS <hex> USERS      -> COMMIT_WELCOME <hex> or NO_COMMIT
// COMMIT <hex>               -> COMMIT_OK / COMMIT_IGNORED / COMMIT_FAILED
// WELCOME <hex> USERS        -> WELCOME_OK / WELCOME_FAILED
// RESET                      -> OK
// QUIT                       -> BYE
static int daveService() {
    DAVESessionHandle session = NULL;
    DAVEEncryptorHandle encryptor = NULL;
    std::map<std::string, DAVEDecryptorHandle> decryptors;
    std::string selfUserID;
    char line[32768];
    while (fgets(line, sizeof(line), stdin)) {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r')) line[--length] = 0;
        char *command = strtok(line, " ");
        if (!command) continue;
        if (strcmp(command, "QUIT") == 0) {
            printResponse("BYE");
            break;
        }
        if (strcmp(command, "RESET") == 0) {
            if (session) daveSessionReset(session);
            if (encryptor) {
                daveEncryptorDestroy(encryptor);
                encryptor = NULL;
            }
            for (std::map<std::string, DAVEDecryptorHandle>::iterator it = decryptors.begin(); it != decryptors.end(); ++it) daveDecryptorDestroy(it->second);
            decryptors.clear();
            printResponse("OK");
            continue;
        }
        if (strcmp(command, "INIT") == 0) {
            char *userID = strtok(NULL, " ");
            char *groupID = strtok(NULL, " ");
            char *end = NULL;
            unsigned long long group = groupID ? strtoull(groupID, &end, 10) : 0;
            if (!userID || !*userID || !groupID || !*groupID || !end || *end) {
                printResponse("ERROR invalid-init");
                continue;
            }
            if (session) daveSessionDestroy(session);
            if (encryptor) {
                daveEncryptorDestroy(encryptor);
                encryptor = NULL;
            }
            for (std::map<std::string, DAVEDecryptorHandle>::iterator it = decryptors.begin(); it != decryptors.end(); ++it) daveDecryptorDestroy(it->second);
            decryptors.clear();
            session = daveSessionCreate(NULL, userID, daveFailure, NULL);
            if (!session) {
                printResponse("ERROR session-create");
                continue;
            }
            selfUserID = userID;
            daveSessionInit(session, daveMaxSupportedProtocolVersion(), (uint64_t)group, userID);
            uint8_t *package = NULL;
            size_t packageLength = 0;
            daveSessionGetMarshalledKeyPackage(session, &package, &packageLength);
            if (!package || !packageLength) {
                if (package) daveFree(package);
                printResponse("ERROR key-package");
                continue;
            }
            printHexResponse("KEY_PACKAGE", package, packageLength);
            daveFree(package);
            continue;
        }
        if (!session) {
            printResponse("ERROR not-initialized");
            continue;
        }
        char *hex = strtok(NULL, " ");
        std::vector<uint8_t> bytes;
        if (strcmp(command, "ACTIVATE") != 0 && strcmp(command, "ENCRYPT") != 0 && strcmp(command, "DECRYPT") != 0 && (!hex || !decodeHex(hex, &bytes))) {
            printResponse("ERROR invalid-hex");
            continue;
        }
        if (strcmp(command, "EXTERNAL_SENDER") == 0) {
            daveSessionSetExternalSender(session, bytes.data(), bytes.size());
            printResponse("OK");
        } else if (strcmp(command, "PROPOSALS") == 0) {
            char *userList = strtok(NULL, " ");
            std::vector<const char *> users;
            splitUserIDs(userList, &users);
            uint8_t *commitWelcome = NULL;
            size_t commitWelcomeLength = 0;
            daveSessionProcessProposals(session, bytes.data(), bytes.size(), users.empty() ? NULL : &users[0], users.size(),
                                        &commitWelcome, &commitWelcomeLength);
            if (commitWelcome && commitWelcomeLength) {
                printHexResponse("COMMIT_WELCOME", commitWelcome, commitWelcomeLength);
                daveFree(commitWelcome);
            } else {
                printResponse("NO_COMMIT");
            }
        } else if (strcmp(command, "COMMIT") == 0) {
            DAVECommitResultHandle result = daveSessionProcessCommit(session, bytes.data(), bytes.size());
            if (!result || daveCommitResultIsFailed(result)) {
                printResponse("COMMIT_FAILED");
            } else if (daveCommitResultIsIgnored(result)) {
                printResponse("COMMIT_IGNORED");
            } else {
                printResponse("COMMIT_OK");
            }
            if (result) daveCommitResultDestroy(result);
        } else if (strcmp(command, "WELCOME") == 0) {
            char *userList = strtok(NULL, " ");
            std::vector<const char *> users;
            splitUserIDs(userList, &users);
            DAVEWelcomeResultHandle result = daveSessionProcessWelcome(session, bytes.data(), bytes.size(),
                                                                         users.empty() ? NULL : &users[0], users.size());
            if (result) {
                daveWelcomeResultDestroy(result);
                printResponse("WELCOME_OK");
            } else {
                printResponse("WELCOME_FAILED");
            }
        } else if (strcmp(command, "ACTIVATE") == 0) {
            char *ssrcText = hex;
            char *end = NULL;
            unsigned long ssrc = ssrcText ? strtoul(ssrcText, &end, 10) : 0;
            if (!ssrcText || !end || *end) {
                printResponse("ERROR invalid-ssrc");
                continue;
            }
            for (std::map<std::string, DAVEDecryptorHandle>::iterator it = decryptors.begin(); it != decryptors.end(); ++it) daveDecryptorDestroy(it->second);
            decryptors.clear();
            DAVEKeyRatchetHandle ratchet = daveSessionGetKeyRatchet(session, selfUserID.c_str());
            if (!ratchet) {
                printResponse("ERROR missing-sender-ratchet");
                continue;
            }
            if (!encryptor) encryptor = daveEncryptorCreate();
            if (!encryptor) {
                daveKeyRatchetDestroy(ratchet);
                printResponse("ERROR encryptor-create");
                continue;
            }
            daveEncryptorAssignSsrcToCodec(encryptor, (uint32_t)ssrc, DAVE_CODEC_OPUS);
            daveEncryptorSetPassthroughMode(encryptor, false);
            daveEncryptorSetKeyRatchet(encryptor, ratchet);
            daveKeyRatchetDestroy(ratchet);
            printResponse(daveEncryptorHasKeyRatchet(encryptor) ? "MEDIA_READY" : "ERROR missing-sender-ratchet");
        } else if (strcmp(command, "ENCRYPT") == 0) {
            char *ssrcText = hex;
            char *opusHex = strtok(NULL, " ");
            char *end = NULL;
            unsigned long ssrc = ssrcText ? strtoul(ssrcText, &end, 10) : 0;
            std::vector<uint8_t> opus;
            if (!encryptor || !ssrcText || !end || *end || !opusHex || !decodeHex(opusHex, &opus)) {
                printResponse("ERROR media-not-ready");
                continue;
            }
            size_t encryptedLength = daveEncryptorGetMaxCiphertextByteSize(encryptor, DAVE_MEDIA_TYPE_AUDIO, opus.size());
            std::vector<uint8_t> encrypted(encryptedLength);
            DAVEEncryptorResultCode result = daveEncryptorEncrypt(encryptor, DAVE_MEDIA_TYPE_AUDIO, (uint32_t)ssrc,
                                                                    opus.data(), opus.size(), encrypted.data(), encrypted.size(), &encryptedLength);
            if (result != DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS) {
                printResponse("ERROR encrypt-failed");
                continue;
            }
            printHexResponse("ENCRYPTED", encrypted.data(), encryptedLength);
        } else if (strcmp(command, "DECRYPT") == 0) {
            char *remoteUserID = hex;
            char *encryptedHex = strtok(NULL, " ");
            std::vector<uint8_t> encrypted;
            if (!remoteUserID || !*remoteUserID || !encryptedHex || !decodeHex(encryptedHex, &encrypted)) {
                printResponse("ERROR invalid-decrypt");
                continue;
            }
            DAVEDecryptorHandle decryptor = decryptors[remoteUserID];
            if (!decryptor) {
                DAVEKeyRatchetHandle ratchet = daveSessionGetKeyRatchet(session, remoteUserID);
                if (!ratchet) {
                    printResponse("ERROR missing-receiver-ratchet");
                    continue;
                }
                decryptor = daveDecryptorCreate();
                if (!decryptor) {
                    daveKeyRatchetDestroy(ratchet);
                    printResponse("ERROR decryptor-create");
                    continue;
                }
                daveDecryptorTransitionToPassthroughMode(decryptor, false);
                daveDecryptorTransitionToKeyRatchet(decryptor, ratchet);
                daveKeyRatchetDestroy(ratchet);
                decryptors[remoteUserID] = decryptor;
            }
            size_t plaintextLength = daveDecryptorGetMaxPlaintextByteSize(decryptor, DAVE_MEDIA_TYPE_AUDIO, encrypted.size());
            std::vector<uint8_t> plaintext(plaintextLength);
            DAVEDecryptorResultCode result = daveDecryptorDecrypt(decryptor, DAVE_MEDIA_TYPE_AUDIO, encrypted.data(), encrypted.size(),
                                                                    plaintext.data(), plaintext.size(), &plaintextLength);
            if (result != DAVE_DECRYPTOR_RESULT_CODE_SUCCESS) {
                printResponse("ERROR decrypt-failed");
                continue;
            }
            printHexResponse("DECRYPTED", plaintext.data(), plaintextLength);
        } else {
            printResponse("ERROR unknown-command");
        }
    }
    if (encryptor) daveEncryptorDestroy(encryptor);
    for (std::map<std::string, DAVEDecryptorHandle>::iterator it = decryptors.begin(); it != decryptors.end(); ++it) daveDecryptorDestroy(it->second);
    if (session) daveSessionDestroy(session);
    return 0;
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
    daveSetLogSinkCallback(daveLog);
    if (argc == 2 && strcmp(argv[1], "--dave-version") == 0) {
        printf("%u\n", daveMaxSupportedProtocolVersion());
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "--capture-test") == 0) return captureTest();
    if (argc == 2 && strcmp(argv[1], "--playback-test") == 0) return playbackTest();
    if (argc == 2 && strcmp(argv[1], "--dave-service") == 0) return daveService();
    if (argc == 4 && strcmp(argv[1], "--key-package") == 0) return keyPackage(argv[2], argv[3]);
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "--self-test") == 0)) return selfTest();
    fprintf(stderr, "Usage: %s [--self-test|--dave-version|--capture-test|--playback-test|--dave-service|--key-package USER_ID GROUP_ID]\n", argv[0]);
    return 64;
}
