//
//  DLVoicePlayback.m
//  Discord Lite
//

#import "DLVoicePlayback.h"
#import <AudioToolbox/AudioQueue.h>

static NSString * const DLVoicePlaybackErrorDomain = @"DLVoicePlaybackError";

static void DLVoicePlaybackCallback(void *userData, AudioQueueRef audioQueue, AudioQueueBufferRef buffer) {
    DLVoicePlayback *playback = (DLVoicePlayback *)userData;
    memset(buffer->mAudioData, 0, buffer->mAudioDataBytesCapacity);
    [playback->lock lock];
    if ([playback->pendingPCM count]) {
        NSData *pcm = [playback->pendingPCM objectAtIndex:0];
        [playback->pendingPCM removeObjectAtIndex:0];
        NSUInteger length = MIN([pcm length], (NSUInteger)buffer->mAudioDataBytesCapacity);
        memcpy(buffer->mAudioData, [pcm bytes], length);
    }
    [playback->lock unlock];
    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
    if (playback->running) AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
}

@implementation DLVoicePlayback

-(id)init {
    self = [super init];
    pendingPCM = [[NSMutableArray alloc] init];
    lock = [[NSLock alloc] init];
    return self;
}

-(void)dealloc {
    [self stop];
    [lock release];
    [pendingPCM release];
    [super dealloc];
}

-(BOOL)start:(NSError **)error {
    if (running) return YES;
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
    AudioQueueRef audioQueue = NULL;
    if (AudioQueueNewOutput(&format, DLVoicePlaybackCallback, self, CFRunLoopGetCurrent(),
                            kCFRunLoopCommonModes, 0, &audioQueue) != noErr) {
        if (error) *error = [NSError errorWithDomain:DLVoicePlaybackErrorDomain code:1 userInfo:nil];
        return NO;
    }
    queue = audioQueue;
    running = YES;
    for (int index = 0; index < 3; index++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(audioQueue, 3840, &buffer) != noErr) {
            [self stop];
            if (error) *error = [NSError errorWithDomain:DLVoicePlaybackErrorDomain code:2 userInfo:nil];
            return NO;
        }
        buffers[index] = buffer;
        DLVoicePlaybackCallback(self, audioQueue, buffer);
    }
    if (AudioQueueStart(audioQueue, NULL) != noErr) {
        [self stop];
        if (error) *error = [NSError errorWithDomain:DLVoicePlaybackErrorDomain code:3 userInfo:nil];
        return NO;
    }
    return YES;
}

-(void)enqueuePCM:(NSData *)pcm {
    if (!running || ![pcm length]) return;
    [lock lock];
    // Limit latency when the renderer falls behind instead of accumulating old speech.
    while ([pendingPCM count] >= 10) [pendingPCM removeObjectAtIndex:0];
    [pendingPCM addObject:pcm];
    [lock unlock];
}

-(void)stop {
    running = NO;
    if (queue) {
        AudioQueueDispose((AudioQueueRef)queue, true);
        queue = NULL;
    }
    memset(buffers, 0, sizeof(buffers));
    [lock lock];
    [pendingPCM removeAllObjects];
    [lock unlock];
}

@end
