//
//  DLCameraCapture.m
//  Discord Lite
//

#import "DLCameraCapture.h"
#import <QTKit/QTKit.h>
#import <QuickTime/QuickTime.h>
#import <CoreVideo/CoreVideo.h>

static NSString * const DLCameraCaptureErrorDomain = @"DLCameraCaptureError";

@interface DLCameraCapture (Encoding)
- (OSStatus)encodedFrame:(ICMEncodedFrameRef)frame error:(OSStatus)error;
@end

static OSStatus DLCameraEncodedFrameCallback(void *context, ICMCompressionSessionRef session,
                                             OSStatus error, ICMEncodedFrameRef frame, void *reserved) {
    return [(DLCameraCapture *)context encodedFrame:frame error:error];
}

static void DLAppendAnnexBNAL(NSMutableData *data, const unsigned char *bytes, NSUInteger length) {
    static const unsigned char startCode[] = { 0, 0, 0, 1 };
    [data appendBytes:startCode length:sizeof(startCode)];
    [data appendBytes:bytes length:length];
}

typedef struct {
    const unsigned char *bytes;
    NSUInteger length;
    NSUInteger bitOffset;
    BOOL valid;
} DLH264BitReader;

typedef struct {
    unsigned char *bytes;
    NSUInteger capacity;
    NSUInteger bitOffset;
    BOOL valid;
} DLH264BitWriter;

static uint32_t DLH264ReadBits(DLH264BitReader *reader, NSUInteger count) {
    uint32_t value = 0;
    NSUInteger i;
    if (!reader->valid || count > 32 || reader->bitOffset + count > reader->length * 8) {
        reader->valid = NO;
        return 0;
    }
    for (i = 0; i < count; i++) {
        NSUInteger offset = reader->bitOffset++;
        value = (value << 1) | ((reader->bytes[offset / 8] >> (7 - (offset % 8))) & 1);
    }
    return value;
}

static uint32_t DLH264ReadUE(DLH264BitReader *reader) {
    NSUInteger zeros = 0;
    uint32_t suffix;
    while (reader->valid && DLH264ReadBits(reader, 1) == 0) {
        zeros++;
        if (zeros > 31) {
            reader->valid = NO;
            return 0;
        }
    }
    if (!reader->valid || !zeros) return 0;
    suffix = DLH264ReadBits(reader, zeros);
    return ((uint32_t)1 << zeros) - 1 + suffix;
}

static void DLH264WriteBits(DLH264BitWriter *writer, uint32_t value, NSUInteger count) {
    NSUInteger i;
    if (!writer->valid || count > 32 || writer->bitOffset + count > writer->capacity * 8) {
        writer->valid = NO;
        return;
    }
    for (i = 0; i < count; i++) {
        NSUInteger offset = writer->bitOffset++;
        unsigned char bit = (unsigned char)((value >> (count - i - 1)) & 1);
        if (bit) writer->bytes[offset / 8] |= (unsigned char)(1 << (7 - (offset % 8)));
    }
}

static void DLH264WriteUE(DLH264BitWriter *writer, uint32_t value) {
    uint32_t codeNum = value + 1;
    NSUInteger bits = 0;
    uint32_t probe = codeNum;
    while (probe) {
        bits++;
        probe >>= 1;
    }
    if (bits > 1) DLH264WriteBits(writer, 0, bits - 1);
    DLH264WriteBits(writer, codeNum, bits);
}

static void DLH264SkipScalingList(DLH264BitReader *reader, NSUInteger size) {
    NSInteger lastScale = 8;
    NSInteger nextScale = 8;
    NSUInteger i;
    for (i = 0; i < size && reader->valid; i++) {
        if (nextScale != 0) {
            uint32_t codeNum = DLH264ReadUE(reader);
            NSInteger deltaScale = (codeNum & 1) ? (NSInteger)((codeNum + 1) / 2) : -(NSInteger)(codeNum / 2);
            nextScale = (lastScale + deltaScale + 256) % 256;
        }
        if (nextScale != 0) lastScale = nextScale;
    }
}

static void DLH264SkipHRD(DLH264BitReader *reader) {
    uint32_t count = DLH264ReadUE(reader);
    uint32_t i;
    DLH264ReadBits(reader, 8);
    if (count > 31) {
        reader->valid = NO;
        return;
    }
    for (i = 0; i <= count && reader->valid; i++) {
        DLH264ReadUE(reader);
        DLH264ReadUE(reader);
        DLH264ReadBits(reader, 1);
    }
    DLH264ReadBits(reader, 20);
}

static BOOL DLH264FindRestrictionFlag(const unsigned char *rbsp, NSUInteger length,
                                      NSUInteger *flagOffset, uint32_t *maxRefFrames,
                                      BOOL *vuiPresent) {
    DLH264BitReader reader;
    uint32_t profile;
    uint32_t picOrderCountType;
    uint32_t cycleCount;
    uint32_t i;
    BOOL nalHRD;
    BOOL vclHRD;
    reader.bytes = rbsp;
    reader.length = length;
    reader.bitOffset = 0;
    reader.valid = YES;

    profile = DLH264ReadBits(&reader, 8);
    DLH264ReadBits(&reader, 16);
    DLH264ReadUE(&reader);
    if (profile == 100 || profile == 110 || profile == 122 || profile == 244 ||
        profile == 44 || profile == 83 || profile == 86 || profile == 118 ||
        profile == 128 || profile == 138 || profile == 144) {
        uint32_t chromaFormat = DLH264ReadUE(&reader);
        if (chromaFormat == 3) DLH264ReadBits(&reader, 1);
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
        DLH264ReadBits(&reader, 1);
        if (DLH264ReadBits(&reader, 1)) {
            NSUInteger scalingCount = chromaFormat == 3 ? 12 : 8;
            for (i = 0; i < scalingCount && reader.valid; i++) {
                if (DLH264ReadBits(&reader, 1)) DLH264SkipScalingList(&reader, i < 6 ? 16 : 64);
            }
        }
    }
    DLH264ReadUE(&reader);
    picOrderCountType = DLH264ReadUE(&reader);
    if (picOrderCountType == 0) {
        DLH264ReadUE(&reader);
    } else if (picOrderCountType == 1) {
        DLH264ReadBits(&reader, 1);
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
        cycleCount = DLH264ReadUE(&reader);
        if (cycleCount > 255) reader.valid = NO;
        for (i = 0; i < cycleCount && reader.valid; i++) DLH264ReadUE(&reader);
    }
    *maxRefFrames = DLH264ReadUE(&reader);
    DLH264ReadBits(&reader, 1);
    DLH264ReadUE(&reader);
    DLH264ReadUE(&reader);
    if (!DLH264ReadBits(&reader, 1)) DLH264ReadBits(&reader, 1);
    DLH264ReadBits(&reader, 1);
    if (DLH264ReadBits(&reader, 1)) {
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
    }

    *flagOffset = reader.bitOffset;
    *vuiPresent = DLH264ReadBits(&reader, 1) != 0;
    if (!reader.valid || !*vuiPresent) return reader.valid;
    if (DLH264ReadBits(&reader, 1)) {
        if (DLH264ReadBits(&reader, 8) == 255) DLH264ReadBits(&reader, 32);
    }
    if (DLH264ReadBits(&reader, 1)) DLH264ReadBits(&reader, 1);
    if (DLH264ReadBits(&reader, 1)) {
        DLH264ReadBits(&reader, 4);
        if (DLH264ReadBits(&reader, 1)) DLH264ReadBits(&reader, 24);
    }
    if (DLH264ReadBits(&reader, 1)) {
        DLH264ReadUE(&reader);
        DLH264ReadUE(&reader);
    }
    if (DLH264ReadBits(&reader, 1)) {
        DLH264ReadBits(&reader, 32);
        DLH264ReadBits(&reader, 32);
        DLH264ReadBits(&reader, 1);
    }
    nalHRD = DLH264ReadBits(&reader, 1) != 0;
    if (nalHRD) DLH264SkipHRD(&reader);
    vclHRD = DLH264ReadBits(&reader, 1) != 0;
    if (vclHRD) DLH264SkipHRD(&reader);
    if (nalHRD || vclHRD) DLH264ReadBits(&reader, 1);
    DLH264ReadBits(&reader, 1);
    *flagOffset = reader.bitOffset;
    return reader.valid;
}

static NSData *DLRewriteH264SPS(const unsigned char *nal, NSUInteger length, BOOL *didRewrite) {
    unsigned char *rbsp;
    unsigned char *rewrittenRBSP;
    unsigned char *ebsp;
    NSUInteger rbspLength = 0;
    NSUInteger rewrittenCapacity;
    NSUInteger i;
    NSUInteger flagOffset = 0;
    uint32_t maxRefFrames = 0;
    BOOL vuiPresent = NO;
    DLH264BitReader source;
    DLH264BitWriter writer;
    NSUInteger ebspLength = 0;
    NSUInteger zeroCount = 0;
    NSData *result;
    if (didRewrite) *didRewrite = NO;
    if (!nal || length < 2 || (nal[0] & 0x1f) != 7) return nil;

    rbsp = (unsigned char *)malloc(length);
    if (!rbsp) return nil;
    for (i = 1; i < length; i++) {
        if (i + 1 < length && i >= 3 && nal[i] == 3 && nal[i - 1] == 0 && nal[i - 2] == 0) continue;
        rbsp[rbspLength++] = nal[i];
    }
    if (!DLH264FindRestrictionFlag(rbsp, rbspLength, &flagOffset, &maxRefFrames, &vuiPresent)) {
        free(rbsp);
        return nil;
    }

    source.bytes = rbsp;
    source.length = rbspLength;
    source.bitOffset = 0;
    source.valid = YES;
    rewrittenCapacity = rbspLength * 2 + 32;
    rewrittenRBSP = (unsigned char *)calloc(rewrittenCapacity, 1);
    if (!rewrittenRBSP) {
        free(rbsp);
        return nil;
    }
    writer.bytes = rewrittenRBSP;
    writer.capacity = rewrittenCapacity;
    writer.bitOffset = 0;
    writer.valid = YES;
    for (i = 0; i < flagOffset; i++) DLH264WriteBits(&writer, DLH264ReadBits(&source, 1), 1);
    if (!vuiPresent) {
        DLH264WriteBits(&writer, 1, 1);
        DLH264WriteBits(&writer, 0, 8);
    }
    DLH264WriteBits(&writer, 1, 1);
    DLH264WriteBits(&writer, 1, 1);
    DLH264WriteUE(&writer, 2);
    DLH264WriteUE(&writer, 1);
    DLH264WriteUE(&writer, 16);
    DLH264WriteUE(&writer, 16);
    DLH264WriteUE(&writer, 0);
    DLH264WriteUE(&writer, maxRefFrames);
    DLH264WriteBits(&writer, 1, 1);
    while (writer.bitOffset % 8) DLH264WriteBits(&writer, 0, 1);
    if (!source.valid || !writer.valid) {
        free(rewrittenRBSP);
        free(rbsp);
        return nil;
    }

    ebsp = (unsigned char *)malloc(writer.bitOffset / 8 * 2 + 2);
    if (!ebsp) {
        free(rewrittenRBSP);
        free(rbsp);
        return nil;
    }
    ebsp[ebspLength++] = nal[0];
    for (i = 0; i < writer.bitOffset / 8; i++) {
        unsigned char byte = rewrittenRBSP[i];
        if (zeroCount >= 2 && byte <= 3) {
            ebsp[ebspLength++] = 3;
            zeroCount = 0;
        }
        ebsp[ebspLength++] = byte;
        zeroCount = byte == 0 ? zeroCount + 1 : 0;
    }
    result = [NSData dataWithBytes:ebsp length:ebspLength];
    if (didRewrite) *didRewrite = YES;
    free(ebsp);
    free(rewrittenRBSP);
    free(rbsp);
    return result;
}

static void DLAppendParameterSets(NSMutableData *data, ImageDescriptionHandle description) {
    Handle extension = NULL;
    if (!description || GetImageDescriptionExtension(description, &extension, 'avcC', 1) != noErr || !extension) return;
    HLock(extension);
    const unsigned char *bytes = (const unsigned char *)*extension;
    Size size = GetHandleSize(extension);
    NSUInteger offset = 6;
    if (size >= 7) {
        NSUInteger spsCount = bytes[5] & 0x1f;
        NSUInteger i;
        for (i = 0; i < spsCount && offset + 2 <= (NSUInteger)size; i++) {
            NSUInteger length = ((NSUInteger)bytes[offset] << 8) | bytes[offset + 1];
            BOOL didRewrite = NO;
            NSData *rewritten;
            offset += 2;
            if (offset + length > (NSUInteger)size) break;
            rewritten = DLRewriteH264SPS(bytes + offset, length, &didRewrite);
            if (rewritten) {
                DLAppendAnnexBNAL(data, [rewritten bytes], [rewritten length]);
                if (didRewrite) NSLog(@"Camera rewrote H.264 SPS with WebRTC bitstream restrictions");
            } else {
                DLAppendAnnexBNAL(data, bytes + offset, length);
            }
            offset += length;
        }
        if (offset < (NSUInteger)size) {
            NSUInteger ppsCount = bytes[offset++];
            for (i = 0; i < ppsCount && offset + 2 <= (NSUInteger)size; i++) {
                NSUInteger length = ((NSUInteger)bytes[offset] << 8) | bytes[offset + 1];
                offset += 2;
                if (offset + length > (NSUInteger)size) break;
                DLAppendAnnexBNAL(data, bytes + offset, length);
                offset += length;
            }
        }
    }
    HUnlock(extension);
    DisposeHandle(extension);
}

@implementation DLCameraCapture

- (id)initWithFrame:(NSRect)frame {
    self = [super init];
    if (self) {
        previewView = [[QTCaptureView alloc] initWithFrame:frame];
        [previewView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [previewView setFillColor:[NSColor colorWithCalibratedWhite:0.08f alpha:1.0f]];
    }
    return self;
}

- (void)dealloc {
    [self stop];
    [previewView release];
    [super dealloc];
}

- (NSView *)previewView {
    return previewView;
}

- (void)setDelegate:(id<DLCameraCaptureDelegate>)inDelegate {
    delegate = inDelegate;
}

- (BOOL)start:(NSError **)error {
    if (running) return YES;

    QTCaptureDevice *device = [QTCaptureDevice defaultInputDeviceWithMediaType:QTMediaTypeVideo];
    if (!device) {
        if (error) {
            *error = [NSError errorWithDomain:DLCameraCaptureErrorDomain
                                         code:1
                                     userInfo:[NSDictionary dictionaryWithObject:@"No camera was found."
                                                                          forKey:NSLocalizedDescriptionKey]];
        }
        return NO;
    }

    NSError *openError = nil;
    if (![device open:&openError]) {
        if (error) *error = openError;
        return NO;
    }

    QTCaptureSession *session = [[QTCaptureSession alloc] init];
    QTCaptureDeviceInput *input = [[QTCaptureDeviceInput alloc] initWithDevice:device];
    NSError *inputError = nil;
    if (![session addInput:input error:&inputError]) {
        [input release];
        [session release];
        [device close];
        if (error) *error = inputError;
        return NO;
    }

    QTCaptureDecompressedVideoOutput *output = [[QTCaptureDecompressedVideoOutput alloc] init];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
                                [NSNumber numberWithInt:320], kCVPixelBufferWidthKey,
                                [NSNumber numberWithInt:240], kCVPixelBufferHeightKey, nil];
    [output setPixelBufferAttributes:attributes];
    [output setMinimumVideoFrameInterval:(1.0 / 15.0)];
    [output setAutomaticallyDropsLateVideoFrames:YES];
    [output setDelegate:self];
    NSError *outputError = nil;
    if (![session addOutput:output error:&outputError]) {
        [output release];
        [input release];
        [session release];
        [device close];
        if (error) *error = outputError;
        return NO;
    }

    ICMCompressionSessionOptionsRef options = NULL;
    ICMCompressionSessionRef compressor = NULL;
    ICMEncodedFrameOutputRecord outputRecord;
    memset(&outputRecord, 0, sizeof(outputRecord));
    outputRecord.encodedFrameOutputCallback = DLCameraEncodedFrameCallback;
    outputRecord.encodedFrameOutputRefCon = self;
    OSStatus status = ICMCompressionSessionOptionsCreate(NULL, &options);
    if (status == noErr) status = ICMCompressionSessionOptionsSetAllowTemporalCompression(options, true);
    if (status == noErr) status = ICMCompressionSessionOptionsSetAllowFrameReordering(options, false);
    if (status == noErr) status = ICMCompressionSessionOptionsSetMaxKeyFrameInterval(options, 30);
    if (status == noErr) status = ICMCompressionSessionCreate(NULL, 320, 240, kH264CodecType, 90000,
                                                              options, NULL, &outputRecord, &compressor);
    if (options) ICMCompressionSessionOptionsRelease(options);
    if (status != noErr || !compressor) {
        [session removeOutput:output];
        [output release];
        [input release];
        [session release];
        [device close];
        if (error) {
            *error = [NSError errorWithDomain:DLCameraCaptureErrorDomain code:status
                                     userInfo:[NSDictionary dictionaryWithObject:@"The H.264 camera encoder could not start."
                                                                          forKey:NSLocalizedDescriptionKey]];
        }
        return NO;
    }

    captureDevice = [device retain];
    captureInput = input;
    captureSession = session;
    videoOutput = output;
    compressionSession = compressor;
    frameNumber = 0;
    [previewView setCaptureSession:captureSession];
    [captureSession startRunning];
    running = YES;
    return YES;
}

- (void)stop {
    if (captureSession) [captureSession stopRunning];
    if (videoOutput) [videoOutput setDelegate:nil];
    if (compressionSession) {
        ICMCompressionSessionCompleteFrames((ICMCompressionSessionRef)compressionSession, true, 0, 0);
        ICMCompressionSessionRelease((ICMCompressionSessionRef)compressionSession);
        compressionSession = NULL;
    }
    [previewView setCaptureSession:nil];
    if (captureDevice && [captureDevice isOpen]) [captureDevice close];
    [captureInput release];
    captureInput = nil;
    [captureSession release];
    captureSession = nil;
    [captureDevice release];
    captureDevice = nil;
    [videoOutput release];
    videoOutput = nil;
    running = NO;
}

- (BOOL)isRunning {
    return running;
}

- (void)requestKeyFrame {
    forceKeyFrame = YES;
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput didOutputVideoFrame:(CVImageBufferRef)videoFrame
     withSampleBuffer:(QTSampleBuffer *)sampleBuffer fromConnection:(QTCaptureConnection *)connection {
    if (!running || !compressionSession || !videoFrame) return;
    TimeValue64 timestamp = (TimeValue64)frameNumber * 6000;
    frameNumber++;
    BOOL shouldForceKeyFrame = forceKeyFrame;
    ICMCompressionFrameOptionsRef frameOptions = NULL;
    if (shouldForceKeyFrame && ICMCompressionFrameOptionsCreate(NULL,
            (ICMCompressionSessionRef)compressionSession, &frameOptions) == noErr) {
        ICMCompressionFrameOptionsSetForceKeyFrame(frameOptions, true);
    }
    OSStatus status = ICMCompressionSessionEncodeFrame((ICMCompressionSessionRef)compressionSession,
                                     (CVPixelBufferRef)videoFrame, timestamp, 6000,
                                     kICMValidTime_DisplayTimeStampIsValid | kICMValidTime_DisplayDurationIsValid,
                                     frameOptions, NULL, NULL);
    if (frameOptions) ICMCompressionFrameOptionsRelease(frameOptions);
    if (shouldForceKeyFrame && status == noErr) forceKeyFrame = NO;
}

- (OSStatus)encodedFrame:(ICMEncodedFrameRef)encodedFrame error:(OSStatus)error {
    if (error != noErr || !encodedFrame || !running) return error;
    const unsigned char *bytes = ICMEncodedFrameGetDataPtr(encodedFrame);
    NSUInteger size = (NSUInteger)ICMEncodedFrameGetDataSize(encodedFrame);
    if (!bytes || size < 4) return noErr;

    BOOL keyFrame = (ICMEncodedFrameGetMediaSampleFlags(encodedFrame) & mediaSampleNotSync) == 0;
    NSMutableData *annexB = [NSMutableData data];
    if (keyFrame) {
        ImageDescriptionHandle description = NULL;
        if (ICMEncodedFrameGetImageDescription(encodedFrame, &description) == noErr) {
            DLAppendParameterSets(annexB, description);
        }
    }
    NSUInteger offset = 0;
    while (offset + 4 <= size) {
        NSUInteger length = ((NSUInteger)bytes[offset] << 24) | ((NSUInteger)bytes[offset + 1] << 16) |
                            ((NSUInteger)bytes[offset + 2] << 8) | bytes[offset + 3];
        offset += 4;
        if (!length || offset + length > size) break;
        DLAppendAnnexBNAL(annexB, bytes + offset, length);
        offset += length;
    }
    if ([annexB length] && [delegate respondsToSelector:@selector(cameraCapture:didEncodeH264Frame:timestamp:)]) {
        [delegate cameraCapture:self didEncodeH264Frame:annexB
                      timestamp:(uint32_t)ICMEncodedFrameGetDisplayTimeStamp(encodedFrame)];
    }
    return noErr;
}

@end
