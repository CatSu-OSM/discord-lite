//
//  DLVoiceMedia.m
//  Discord Lite
//

#import "DLVoiceMedia.h"

#include <opus/opus.h>
#include <sodium.h>

static NSString * const DLVoiceMediaErrorDomain = @"DLVoiceMediaError";

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
    [super dealloc];
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
