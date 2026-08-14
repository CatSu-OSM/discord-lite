// 20 ms, 48 kHz stereo microphone capture for the Lion voice path.
#import <Foundation/Foundation.h>

@protocol DLVoiceCaptureDelegate <NSObject>
-(void)voiceCaptureDidReceivePCM:(NSData *)pcm;
@end

@interface DLVoiceCapture : NSObject {
@public
    id<DLVoiceCaptureDelegate> delegate;
    void *queue;
    void *buffers[3];
    NSMutableData *pendingPCM;
    BOOL running;
}

-(id)initWithDelegate:(id<DLVoiceCaptureDelegate>)inDelegate;
+(NSArray *)inputDevices;
-(BOOL)start:(NSError **)error;
-(void)stop;

@end
