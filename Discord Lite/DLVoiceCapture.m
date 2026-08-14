//
//  DLVoiceCapture.m
//  Discord Lite
//

#import "DLVoiceCapture.h"
#import <AudioToolbox/AudioQueue.h>

static NSString * const DLVoiceCaptureErrorDomain = @"DLVoiceCaptureError";

static void DLVoiceCaptureCallback(void *userData, AudioQueueRef audioQueue, AudioQueueBufferRef buffer,
                                   const AudioTimeStamp *startTime, UInt32 packetCount, const AudioStreamPacketDescription *packetDescriptions) {
    DLVoiceCapture *capture = (DLVoiceCapture *)userData;
    if (capture->running && buffer->mAudioDataByteSize) {
        // Input devices are allowed to return partial AudioQueue buffers.
        // Discord/Opus needs exactly 20 ms (960 stereo frames), so combine
        // callbacks here rather than silently dropping every non-3840-byte one.
        [capture->pendingPCM appendBytes:buffer->mAudioData length:buffer->mAudioDataByteSize];
        while ([capture->pendingPCM length] >= 3840) {
            NSData *pcm = [NSData dataWithBytes:[capture->pendingPCM bytes] length:3840];
            [capture->pendingPCM replaceBytesInRange:NSMakeRange(0, 3840) withBytes:NULL length:0];
            [(NSObject *)capture->delegate performSelectorOnMainThread:@selector(voiceCaptureDidReceivePCM:)
                                                              withObject:pcm waitUntilDone:NO];
        }
    }
    if (capture->running) {
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
    }
}

@implementation DLVoiceCapture

-(id)initWithDelegate:(id<DLVoiceCaptureDelegate>)inDelegate {
    self = [super init];
    delegate = inDelegate;
    pendingPCM = [[NSMutableData alloc] init];
    return self;
}

-(void)dealloc {
    [self stop];
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
    if (AudioQueueNewInput(&format, DLVoiceCaptureCallback, self, CFRunLoopGetCurrent(),
                           kCFRunLoopCommonModes, 0, &audioQueue) != noErr) {
        if (error) *error = [NSError errorWithDomain:DLVoiceCaptureErrorDomain code:1 userInfo:nil];
        return NO;
    }
    queue = audioQueue;
    for (int index = 0; index < 3; index++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(audioQueue, 3840, &buffer) != noErr) {
            [self stop];
            if (error) *error = [NSError errorWithDomain:DLVoiceCaptureErrorDomain code:2 userInfo:nil];
            return NO;
        }
        buffers[index] = buffer;
        buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
        AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
    }
    running = YES;
    if (AudioQueueStart(audioQueue, NULL) != noErr) {
        [self stop];
        if (error) *error = [NSError errorWithDomain:DLVoiceCaptureErrorDomain code:3 userInfo:nil];
        return NO;
    }
    return YES;
}

-(void)stop {
    running = NO;
    if (queue) {
        AudioQueueDispose((AudioQueueRef)queue, true);
        queue = NULL;
    }
    memset(buffers, 0, sizeof(buffers));
    [pendingPCM setLength:0];
}

@end
