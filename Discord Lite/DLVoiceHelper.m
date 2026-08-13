//
//  DLVoiceHelper.m
//  Discord Lite
//

#import <Cocoa/Cocoa.h>
#import "DLVoiceHelper.h"

@implementation DLVoiceHelper

-(id)init {
    self = [super init];
    pendingOutput = [[NSMutableData alloc] init];
    return self;
}

-(void)dealloc {
    [self stop];
    [pendingOutput release];
    [super dealloc];
}

-(BOOL)startForUserID:(NSString *)userID groupID:(NSString *)groupID error:(NSString **)error {
    if (NSAppKitVersionNumber < 1138.0) {
        if (error) *error = @"Encrypted voice requires OS X 10.7 or later.";
        return NO;
    }
    if (![userID length] || ![groupID length]) {
        if (error) *error = @"The voice session is missing a user or group identifier.";
        return NO;
    }
    [self stop];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"DiscordLiteVoiceHelper" ofType:nil];
    if (![path length] || ![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        if (error) *error = @"The Lion voice helper is missing from the application bundle.";
        return NO;
    }
    task = [[NSTask alloc] init];
    input = [[NSPipe pipe] retain];
    NSPipe *outputPipe = [NSPipe pipe];
    output = [outputPipe fileHandleForReading];
    [output retain];
    [task setLaunchPath:path];
    [task setArguments:[NSArray arrayWithObject:@"--dave-service"]];
    [task setStandardInput:input];
    [task setStandardOutput:outputPipe];
    [task setStandardError:[NSFileHandle fileHandleForWritingAtPath:@"/dev/null"]];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        if (error) *error = [exception reason];
        [self stop];
        return NO;
    }
    NSString *response = [self sendCommand:[NSString stringWithFormat:@"INIT %@ %@", userID, groupID] error:error];
    if (![response hasPrefix:@"KEY_PACKAGE "]) {
        [self stop];
        return NO;
    }
    return YES;
}

-(NSString *)sendCommand:(NSString *)command error:(NSString **)error {
    if (!task || ![task isRunning] || !input || !output || ![command length]) {
        if (error) *error = @"The Lion voice helper is not running.";
        return nil;
    }
    NSData *request = [[command stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    @try {
        [[input fileHandleForWriting] writeData:request];
        while (YES) {
            NSRange newline = [pendingOutput rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                                 options:0 range:NSMakeRange(0, [pendingOutput length])];
            if (newline.location != NSNotFound) {
                NSData *line = [pendingOutput subdataWithRange:NSMakeRange(0, newline.location)];
                [pendingOutput replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
                return [[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] autorelease];
            }
            NSData *available = [output availableData];
            if (![available length]) break;
            [pendingOutput appendData:available];
        }
    } @catch (NSException *exception) {
        if (error) *error = [exception reason];
        return nil;
    }
    if (error) *error = @"The Lion voice helper stopped before it replied.";
    return nil;
}

-(void)stop {
    if (task && [task isRunning]) {
        @try {
            [[input fileHandleForWriting] writeData:[@"QUIT\n" dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *exception) {
        }
        [task terminate];
    }
    [input release];
    input = nil;
    [output release];
    output = nil;
    [task release];
    task = nil;
    [pendingOutput setLength:0];
}

@end
