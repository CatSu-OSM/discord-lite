//
//  DLVoiceMedia.m
//  Discord Lite
//

#import "DLVoiceMedia.h"

#include <opus/opus.h>
#include <sodium.h>
#include <arpa/inet.h>

static NSString * const DLVoiceMediaErrorDomain = @"DLVoiceMediaError";

static NSUInteger DLRTPHeaderLength(const unsigned char *bytes, NSUInteger length, NSUInteger *encryptedExtensionLength) {
    if (encryptedExtensionLength) *encryptedExtensionLength = 0;
    if (length < 12 || (bytes[0] >> 6) != 2) return 0;
    NSUInteger headerLength = 12 + ((bytes[0] & 0x0f) * 4);
    if (headerLength > length) return 0;
    if ((bytes[0] & 0x10) != 0) {
        if (headerLength + 4 > length) return 0;
        NSUInteger extensionWords = ((NSUInteger)bytes[headerLength + 2] << 8) | bytes[headerLength + 3];
        // RTP-size AEAD leaves the extension preamble in the authenticated
        // header, but encrypts the extension elements with the media payload.
        if (encryptedExtensionLength) *encryptedExtensionLength = extensionWords * 4;
        headerLength += 4;
    }
    return headerLength <= length ? headerLength : 0;
}

@implementation DLVoiceMedia

+ (BOOL)isAvailable {
    return sodium_init() >= 0;
}

- (id)initWithChannels:(int)channelCount {
    self = [super init];
    if (self) {
        if (channelCount < 1 || channelCount > 2) {
            [self release];
            return nil;
        }
        self->channels = channelCount;
        int opusError = OPUS_OK;
        encoder = opus_encoder_create(48000, channelCount, OPUS_APPLICATION_VOIP, &opusError);
        if (opusError != OPUS_OK) {
            [self release];
            return nil;
        }
        decoder = opus_decoder_create(48000, channelCount, &opusError);
        if (opusError != OPUS_OK) {
            opus_encoder_destroy((OpusEncoder *)encoder);
            [self release];
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (encoder) opus_encoder_destroy((OpusEncoder *)encoder);
    if (decoder) opus_decoder_destroy((OpusDecoder *)decoder);
    [transportKey release];
    [super dealloc];
}

- (BOOL)setXChaChaTransportKey:(NSData *)key error:(NSError **)error {
    if ([key length] != crypto_aead_xchacha20poly1305_ietf_KEYBYTES) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-100 userInfo:nil];
        return NO;
    }
    [transportKey release];
    transportKey = [key copy];
    transportNonce = 0;
    return YES;
}

- (NSData *)encryptOpus:(NSData *)opus rtpHeader:(NSData *)header error:(NSError **)error {
    if (!transportKey || !opus || ![opus length] || DLRTPHeaderLength([header bytes], [header length], NULL) != [header length]) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-101 userInfo:nil];
        return nil;
    }
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    memset(nonce, 0, sizeof(nonce));
    uint32_t networkNonce = htonl(transportNonce++);
    memcpy(nonce, &networkNonce, sizeof(networkNonce));
    NSMutableData *packet = [NSMutableData dataWithData:header];
    unsigned long long encryptedLength = 0;
    NSMutableData *encrypted = [NSMutableData dataWithLength:[opus length] + crypto_aead_xchacha20poly1305_ietf_ABYTES];
    if (crypto_aead_xchacha20poly1305_ietf_encrypt([encrypted mutableBytes], &encryptedLength,
                                                    [opus bytes], [opus length], [header bytes], [header length],
                                                    NULL, nonce, [transportKey bytes]) != 0) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-102 userInfo:nil];
        return nil;
    }
    [encrypted setLength:(NSUInteger)encryptedLength];
    [packet appendData:encrypted];
    [packet appendBytes:nonce length:sizeof(networkNonce)];
    return packet;
}

- (NSData *)decryptVoicePacket:(NSData *)packet error:(NSError **)error {
    const unsigned char *bytes = [packet bytes];
    NSUInteger encryptedExtensionLength = 0;
    NSUInteger headerLength = DLRTPHeaderLength(bytes, [packet length], &encryptedExtensionLength);
    NSUInteger nonceLength = sizeof(uint32_t);
    if (!transportKey || !headerLength || [packet length] < headerLength + nonceLength + crypto_aead_xchacha20poly1305_ietf_ABYTES) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-103 userInfo:nil];
        return nil;
    }
    NSUInteger encryptedLength = [packet length] - headerLength - nonceLength;
    unsigned char nonce[crypto_aead_xchacha20poly1305_ietf_NPUBBYTES];
    memset(nonce, 0, sizeof(nonce));
    memcpy(nonce, bytes + [packet length] - nonceLength, nonceLength);
    NSMutableData *opus = [NSMutableData dataWithLength:encryptedLength];
    unsigned long long opusLength = 0;
    if (crypto_aead_xchacha20poly1305_ietf_decrypt([opus mutableBytes], &opusLength, NULL,
                                                    bytes + headerLength, encryptedLength, bytes, headerLength,
                                                    nonce, [transportKey bytes]) != 0) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-104 userInfo:nil];
        return nil;
    }
    [opus setLength:(NSUInteger)opusLength];
    if (encryptedExtensionLength > [opus length]) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:-105 userInfo:nil];
        return nil;
    }
    if (encryptedExtensionLength) {
        [opus replaceBytesInRange:NSMakeRange(0, encryptedExtensionLength) withBytes:NULL length:0];
    }
    return opus;
}

- (NSData *)encodePCM:(NSData *)pcm frameCount:(int)frameCount error:(NSError **)error {
    if (!encoder || frameCount <= 0 || [pcm length] == 0) return nil;
    unsigned char compressed[4000];
    int length = opus_encode((OpusEncoder *)encoder, (const opus_int16 *)[pcm bytes], frameCount,
                             compressed, sizeof(compressed));
    if (length < 0) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:length userInfo:nil];
        return nil;
    }
    return [NSData dataWithBytes:compressed length:length];
}

- (NSData *)decodeOpus:(NSData *)packet frameCount:(int)frameCount error:(NSError **)error {
    if (!decoder || frameCount <= 0) return nil;
    NSMutableData *pcm = [NSMutableData dataWithLength:(NSUInteger)frameCount * (NSUInteger)channels * sizeof(opus_int16)];
    int samples = opus_decode((OpusDecoder *)decoder, [packet bytes], (opus_int32)[packet length],
                              (opus_int16 *)[pcm mutableBytes], frameCount, 0);
    if (samples < 0) {
        if (error) *error = [NSError errorWithDomain:DLVoiceMediaErrorDomain code:samples userInfo:nil];
        return nil;
    }
    [pcm setLength:(NSUInteger)samples * (NSUInteger)channels * sizeof(opus_int16)];
    return pcm;
}

@end
