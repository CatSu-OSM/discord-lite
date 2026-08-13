// CoreAudio speaker queue for decoded 48 kHz stereo voice PCM.
#import <Foundation/Foundation.h>

@interface DLVoicePlayback : NSObject {
@public
    void *queue;
    void *buffers[3];
    NSMutableArray *pendingPCM;
    NSLock *lock;
    BOOL running;
    BOOL queueRetainsPlayback;
}

-(BOOL)start:(NSError **)error;
-(void)enqueuePCM:(NSData *)pcm;
-(void)stop;

@end
