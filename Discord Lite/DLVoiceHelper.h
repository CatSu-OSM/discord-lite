//
//  DLVoiceHelper.h
//  Discord Lite
//
//  The Cocoa target remains 10.6-compatible.  This class talks to the
//  separately bundled 10.7+ DAVE process over local pipes.
//

#import <Foundation/Foundation.h>

@interface DLVoiceHelper : NSObject {
    NSTask *task;
    NSPipe *input;
    NSFileHandle *output;
    NSMutableData *pendingOutput;
    NSString *initialKeyPackage;
    NSData *externalSenderPackage;
}

-(BOOL)startForUserID:(NSString *)userID groupID:(NSString *)groupID error:(NSString **)error;
-(NSString *)initialKeyPackage;
-(BOOL)setExternalSenderPackage:(NSData *)package error:(NSString **)error;
-(NSString *)sendCommand:(NSString *)command error:(NSString **)error;
-(void)stop;

@end
