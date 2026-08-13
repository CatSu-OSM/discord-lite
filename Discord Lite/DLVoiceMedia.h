//
//  DLVoiceMedia.h
//  Discord Lite
//
//  Opus codec and modern transport-crypto boundary for the 10.7+ voice path.
//

#import <Foundation/Foundation.h>

@interface DLVoiceMedia : NSObject {
    void *encoder;
    void *decoder;
    int channels;
    NSData *transportKey;
    uint32_t transportNonce;
}

+ (BOOL)isAvailable;
- (id)initWithChannels:(int)channelCount;
- (NSData *)encodePCM:(NSData *)pcm frameCount:(int)frameCount error:(NSError **)error;
- (NSData *)decodeOpus:(NSData *)packet frameCount:(int)frameCount error:(NSError **)error;
- (BOOL)setXChaChaTransportKey:(NSData *)key error:(NSError **)error;
- (NSData *)encryptOpus:(NSData *)opus rtpHeader:(NSData *)header error:(NSError **)error;
- (NSData *)decryptVoicePacket:(NSData *)packet error:(NSError **)error;

@end
