//
//  DLCameraCapture.h
//  Discord Lite
//
//  QTKit camera preview for the legacy 10.6+ client.
//

#import <Cocoa/Cocoa.h>

@class QTCaptureSession;
@class QTCaptureDevice;
@class QTCaptureDeviceInput;
@class QTCaptureView;

@class DLCameraCapture;
@protocol DLCameraCaptureDelegate <NSObject>
@optional
- (void)cameraCapture:(DLCameraCapture *)capture didEncodeH264Frame:(NSData *)frame timestamp:(uint32_t)timestamp;
@end

@interface DLCameraCapture : NSObject {
    QTCaptureSession *captureSession;
    QTCaptureDevice *captureDevice;
    QTCaptureDeviceInput *captureInput;
    QTCaptureView *previewView;
    id<DLCameraCaptureDelegate> delegate;
    id videoOutput;
    void *compressionSession;
    uint32_t frameNumber;
    BOOL forceKeyFrame;
    BOOL running;
}

- (id)initWithFrame:(NSRect)frame;
- (void)setDelegate:(id<DLCameraCaptureDelegate>)delegate;
- (NSView *)previewView;
- (BOOL)start:(NSError **)error;
- (void)requestKeyFrame;
- (void)stop;
- (BOOL)isRunning;

@end
